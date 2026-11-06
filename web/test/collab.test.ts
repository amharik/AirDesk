import { describe, expect, it } from 'vitest';
import {
  DeviceAttachmentRegistry,
  GroupSessionStore,
  MembershipError,
  MembershipStore,
  permissionsForRole,
  roleHasPermission
} from '../src/collab/membership';
import { SharedResourceStore } from '../src/collab/resources';
import { AuditLog } from '../src/collab/audit';

function workspace(): MembershipStore {
  return new MembershipStore({
    workspaceId: 'ws-1',
    ownerId: 'owner',
    members: [
      { userId: 'editor', role: 'editor' },
      { userId: 'viewer', role: 'viewer' }
    ]
  });
}

describe('collaboration permissions', () => {
  it('defines an explicit owner, editor and viewer permission matrix', () => {
    expect(permissionsForRole('owner')).toContain('member.manage');
    expect(permissionsForRole('editor')).not.toContain('member.manage');
    expect(permissionsForRole('viewer')).not.toContain('workspace.write');

    expect(roleHasPermission('owner', 'workspace.manage')).toBe(true);
    expect(roleHasPermission('editor', 'workspace.write')).toBe(true);
    expect(roleHasPermission('editor', 'resource.write')).toBe(true);
    expect(roleHasPermission('editor', 'resource.manage')).toBe(false);
    expect(roleHasPermission('viewer', 'workspace.read')).toBe(true);
    expect(roleHasPermission('viewer', 'workspace.write')).toBe(false);
    expect(roleHasPermission('viewer', 'resource.write')).toBe(false);
    expect(roleHasPermission('viewer', 'session.open')).toBe(false);
    expect(roleHasPermission('viewer', 'session.join')).toBe(true);
  });

  it('prevents privilege widening by non-owners and blocks owner grants', () => {
    const members = workspace();

    expect(() => members.addMember('editor', { userId: 'new', role: 'viewer' })).toThrow(
      MembershipError
    );
    expect(() => members.changeRole('editor', 'viewer', 'editor')).toThrow(MembershipError);
    expect(() => members.addMember('owner', { userId: 'other-owner', role: 'owner' })).toThrow(
      /CannotGrantOwner/
    );
    expect(() => members.changeRole('owner', 'viewer', 'owner')).toThrow(/CannotGrantOwner/);
    expect(members.roleOf('owner')).toBe('owner');
    expect(members.isMember('new')).toBe(false);
  });

  it('revokes membership immediately without removing audit history', () => {
    const members = workspace();

    expect(members.authorize('editor', 'workspace.write')).toBe(true);
    members.revokeMember('owner', 'editor');

    expect(members.authorize('editor', 'workspace.write')).toBe(false);
    expect(members.isMember('editor')).toBe(false);
    expect(members.member('editor')?.revoked).toBe(true);
    expect(() => members.revokeMember('owner', 'owner')).toThrow(/OwnerImmutable/);
  });

  it('records audit events in append order with monotonic sequence numbers', () => {
    const audit = new AuditLog('ws-1');
    const members = new MembershipStore({
      workspaceId: 'ws-1',
      ownerId: 'owner',
      audit
    });

    members.addMember('owner', { userId: 'editor', role: 'editor' });
    members.changeRole('owner', 'editor', 'viewer');
    members.revokeMember('owner', 'editor');

    expect(audit.events.map((event) => event.seq)).toEqual([1, 2, 3]);
    expect(audit.events.map((event) => event.action)).toEqual([
      'member.added',
      'member.role-changed',
      'member.revoked'
    ]);
    expect(audit.lastSeq).toBe(3);
  });

  it('does not infer membership from device pairing or controller attachment', () => {
    const members = workspace();
    const attachments = new DeviceAttachmentRegistry();

    attachments.pair('phone-1', 'stranger');
    attachments.attachController('tablet-1', 'viewer');

    expect(members.isMember('stranger')).toBe(false);
    expect(members.authorize('stranger', 'workspace.read')).toBe(false);
    expect(attachments.attachment('phone-1')?.kind).toBe('paired');
    expect(attachments.attachment('tablet-1')?.kind).toBe('controller');
    expect(members.authorize('viewer', 'workspace.write')).toBe(false);
  });

  it('keeps group sessions optional and explicit rather than inferred', () => {
    const members = workspace();
    const attachments = new DeviceAttachmentRegistry();
    const sessions = new GroupSessionStore(members);

    attachments.attachController('tablet-1', 'viewer');
    expect(sessions.sessions()).toEqual([]);

    const opened = sessions.open('editor', 'session-1');
    expect(opened.participants).toEqual(['editor']);
    expect(sessions.join('session-1', 'viewer').participants).toEqual(['editor', 'viewer']);
    expect(() => sessions.join('session-1', 'stranger')).toThrow(/PermissionDenied/);
    expect(() => sessions.open('viewer', 'session-2')).toThrow(/PermissionDenied/);
  });
});

describe('shared resources', () => {
  it('allows shared document and application-data access without widening roles', () => {
    const members = workspace();
    const resources = new SharedResourceStore(members);
    const document = resources.add('editor', {
      id: 'doc-1',
      kind: 'document',
      policy: { visibility: 'workspace', defaultAccess: 'read' }
    });

    expect(document.ownerId).toBe('editor');
    expect(resources.authorize('viewer', 'doc-1', 'resource.read')).toBe(true);
    expect(resources.authorize('viewer', 'doc-1', 'resource.write')).toBe(false);
    expect(resources.authorize('editor', 'doc-1', 'resource.write')).toBe(true);
    expect(resources.authorize('editor', 'doc-1', 'resource.manage')).toBe(false);
    expect(resources.authorize('owner', 'doc-1', 'resource.manage')).toBe(true);

    resources.setAccess('editor', 'doc-1', 'viewer', 'write');
    expect(resources.access('viewer', 'doc-1')).toBe('read');
    expect(resources.authorize('viewer', 'doc-1', 'resource.write')).toBe(false);
  });

  it('honors private resource policy and rejects unauthorized policy changes', () => {
    const members = workspace();
    const resources = new SharedResourceStore(members);
    resources.add('editor', {
      id: 'notes',
      kind: 'application-data',
      policy: { visibility: 'private', defaultAccess: 'read' }
    });

    expect(resources.authorize('viewer', 'notes', 'resource.read')).toBe(false);
    expect(resources.authorize('stranger', 'notes', 'resource.read')).toBe(false);
    expect(resources.authorize('editor', 'notes', 'resource.read')).toBe(true);
    expect(() => resources.setAccess('viewer', 'notes', 'viewer', 'write')).toThrow(
      /PermissionDenied/
    );
  });

  it('audits resource access changes after membership events', () => {
    const audit = new AuditLog('ws-1');
    const members = new MembershipStore({
      workspaceId: 'ws-1',
      ownerId: 'owner',
      members: [{ userId: 'editor', role: 'editor' }],
      audit
    });
    const resources = new SharedResourceStore(members, audit);

    members.addMember('owner', { userId: 'viewer', role: 'viewer' });
    resources.add('editor', {
      id: 'doc-1',
      kind: 'document',
      policy: { visibility: 'workspace', defaultAccess: 'read' }
    });
    resources.setAccess('editor', 'doc-1', 'viewer', 'write');

    expect(audit.events.map((event) => event.seq)).toEqual([1, 2, 3]);
    expect(audit.events.map((event) => event.action)).toEqual([
      'member.added',
      'resource.added',
      'resource.access-changed'
    ]);
  });
});
