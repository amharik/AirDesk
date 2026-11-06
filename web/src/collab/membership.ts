import { AuditLog } from './audit';
import type { AuditEvent } from './audit';

export type MemberRole = 'owner' | 'editor' | 'viewer';

export type Permission =
  | 'workspace.read'
  | 'workspace.write'
  | 'workspace.manage'
  | 'member.manage'
  | 'resource.read'
  | 'resource.write'
  | 'resource.manage'
  | 'audit.read'
  | 'session.open'
  | 'session.join';

const OWNER_PERMISSIONS: readonly Permission[] = [
  'workspace.read',
  'workspace.write',
  'workspace.manage',
  'member.manage',
  'resource.read',
  'resource.write',
  'resource.manage',
  'audit.read',
  'session.open',
  'session.join'
];

const ROLE_PERMISSIONS: Record<MemberRole, readonly Permission[]> = {
  owner: OWNER_PERMISSIONS,
  editor: [
    'workspace.read',
    'workspace.write',
    'resource.read',
    'resource.write',
    'session.open',
    'session.join'
  ],
  viewer: ['workspace.read', 'resource.read', 'session.join']
};

export function permissionsForRole(role: MemberRole): readonly Permission[] {
  return ROLE_PERMISSIONS[role];
}

export function roleHasPermission(role: MemberRole, permission: Permission): boolean {
  return ROLE_PERMISSIONS[role].includes(permission);
}

export interface Member {
  userId: string;
  role: MemberRole;
  revoked: boolean;
  joinedAt: number;
}

export interface MemberInput {
  userId: string;
  role: MemberRole;
  joinedAt?: number;
}

export interface MembershipOptions {
  workspaceId: string;
  ownerId: string;
  members?: readonly MemberInput[];
  audit?: AuditLog;
}

export type MembershipErrorCode =
  | 'MemberExists'
  | 'MemberNotFound'
  | 'OwnerImmutable'
  | 'PermissionDenied'
  | 'InvalidRole'
  | 'CannotGrantOwner'
  | 'SessionExists'
  | 'SessionNotFound';

export class MembershipError extends Error {
  readonly code: MembershipErrorCode;

  constructor(code: MembershipErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'MembershipError';
    this.code = code;
  }
}

function cloneMember(member: Member): Member {
  return { ...member };
}

export class MembershipStore {
  private readonly workspaceId: string;
  private readonly ownerId: string;
  private readonly members = new Map<string, Member>();
  private readonly auditLog: AuditLog;

  constructor(options: MembershipOptions) {
    this.workspaceId = options.workspaceId;
    this.ownerId = options.ownerId;
    this.auditLog = options.audit ?? new AuditLog(options.workspaceId);
    this.members.set(options.ownerId, {
      userId: options.ownerId,
      role: 'owner',
      revoked: false,
      joinedAt: Date.now()
    });

    for (const member of options.members ?? []) {
      if (member.userId === options.ownerId) continue;
      if (member.role === 'owner') {
        throw new MembershipError('CannotGrantOwner', 'a workspace has one owner.');
      }
      this.members.set(member.userId, {
        userId: member.userId,
        role: member.role,
        revoked: false,
        joinedAt: member.joinedAt ?? Date.now()
      });
    }
  }

  get state(): {
    workspaceId: string;
    ownerId: string;
    members: readonly Member[];
  } {
    return {
      workspaceId: this.workspaceId,
      ownerId: this.ownerId,
      members: [...this.members.values()].map(cloneMember)
    };
  }

  get audit(): AuditLog {
    return this.auditLog;
  }

  get auditEvents(): readonly AuditEvent[] {
    return this.auditLog.events;
  }

  member(userId: string): Member | null {
    const member = this.members.get(userId);
    return member ? cloneMember(member) : null;
  }

  roleOf(userId: string): MemberRole | null {
    const member = this.members.get(userId);
    if (!member || member.revoked) return null;
    return member.role;
  }

  isMember(userId: string): boolean {
    return this.roleOf(userId) !== null;
  }

  permissions(userId: string): readonly Permission[] {
    const role = this.roleOf(userId);
    return role ? permissionsForRole(role) : [];
  }

  authorize(userId: string, permission: Permission): boolean {
    const role = this.roleOf(userId);
    return role !== null && roleHasPermission(role, permission);
  }

  addMember(actorId: string, input: MemberInput): Member {
    this.requireManage(actorId);
    if (input.role === 'owner') {
      throw new MembershipError('CannotGrantOwner', 'ownership is not transferable by membership.');
    }
    if (this.members.has(input.userId)) {
      throw new MembershipError('MemberExists', 'member already exists.');
    }
    const member: Member = {
      userId: input.userId,
      role: input.role,
      revoked: false,
      joinedAt: input.joinedAt ?? Date.now()
    };
    this.members.set(member.userId, member);
    this.auditLog.append({
      action: 'member.added',
      actorId,
      targetId: member.userId,
      detail: { role: member.role }
    });
    return cloneMember(member);
  }

  changeRole(actorId: string, userId: string, role: MemberRole): Member {
    this.requireManage(actorId);
    if (role === 'owner') {
      throw new MembershipError('CannotGrantOwner', 'ownership is not transferable by membership.');
    }
    if (userId === this.ownerId) {
      throw new MembershipError('OwnerImmutable', 'the owner role cannot be changed.');
    }
    const member = this.members.get(userId);
    if (!member || member.revoked) {
      throw new MembershipError('MemberNotFound', 'member does not exist.');
    }
    const previousRole = member.role;
    const updated: Member = { ...member, role };
    this.members.set(userId, updated);
    this.auditLog.append({
      action: 'member.role-changed',
      actorId,
      targetId: userId,
      detail: { from: previousRole, to: role }
    });
    return cloneMember(updated);
  }

  revokeMember(actorId: string, userId: string): Member {
    this.requireManage(actorId);
    if (userId === this.ownerId) {
      throw new MembershipError('OwnerImmutable', 'the owner cannot be revoked.');
    }
    const member = this.members.get(userId);
    if (!member) {
      throw new MembershipError('MemberNotFound', 'member does not exist.');
    }
    if (member.revoked) {
      return cloneMember(member);
    }
    const updated: Member = { ...member, revoked: true };
    this.members.set(userId, updated);
    this.auditLog.append({
      action: 'member.revoked',
      actorId,
      targetId: userId
    });
    return cloneMember(updated);
  }

  private requireManage(actorId: string): void {
    if (!this.authorize(actorId, 'member.manage')) {
      throw new MembershipError('PermissionDenied', 'member management is not permitted.');
    }
  }
}

export type AttachmentKind = 'paired' | 'controller';

export interface DeviceAttachment {
  deviceId: string;
  userId?: string;
  kind: AttachmentKind;
  attachedAt: number;
}

function cloneAttachment(attachment: DeviceAttachment): DeviceAttachment {
  return { ...attachment };
}

export class DeviceAttachmentRegistry {
  private readonly attachmentsByDevice = new Map<string, DeviceAttachment>();

  pair(deviceId: string, userId?: string, attachedAt = Date.now()): DeviceAttachment {
    return this.record(deviceId, userId, 'paired', attachedAt);
  }

  attachController(deviceId: string, userId?: string, attachedAt = Date.now()): DeviceAttachment {
    return this.record(deviceId, userId, 'controller', attachedAt);
  }

  attachment(deviceId: string): DeviceAttachment | null {
    const attachment = this.attachmentsByDevice.get(deviceId);
    return attachment ? cloneAttachment(attachment) : null;
  }

  attachments(): readonly DeviceAttachment[] {
    return [...this.attachmentsByDevice.values()].map(cloneAttachment);
  }

  private record(
    deviceId: string,
    userId: string | undefined,
    kind: AttachmentKind,
    attachedAt: number
  ): DeviceAttachment {
    const attachment: DeviceAttachment = {
      deviceId,
      ...(userId ? { userId } : {}),
      kind,
      attachedAt
    };
    this.attachmentsByDevice.set(deviceId, attachment);
    return cloneAttachment(attachment);
  }
}

export interface GroupSession {
  id: string;
  workspaceId: string;
  hostId: string;
  participants: readonly string[];
}

function cloneSession(session: GroupSession): GroupSession {
  return { ...session, participants: [...session.participants] };
}

export class GroupSessionStore {
  private readonly sessionsById = new Map<string, GroupSession>();

  constructor(private readonly membership: MembershipStore) {}

  open(hostId: string, sessionId: string, at = Date.now()): GroupSession {
    if (!this.membership.authorize(hostId, 'session.open')) {
      throw new MembershipError('PermissionDenied', 'group sessions require explicit permission.');
    }
    if (this.sessionsById.has(sessionId)) {
      throw new MembershipError('SessionExists', 'group session already exists.');
    }
    const session: GroupSession = {
      id: sessionId,
      workspaceId: this.membership.state.workspaceId,
      hostId,
      participants: [hostId]
    };
    this.sessionsById.set(sessionId, session);
    this.membership.audit.append({
      action: 'session.opened',
      actorId: hostId,
      targetId: sessionId,
      at
    });
    return cloneSession(session);
  }

  join(sessionId: string, userId: string, at = Date.now()): GroupSession {
    const session = this.sessionsById.get(sessionId);
    if (!session) {
      throw new MembershipError('SessionNotFound', 'group session does not exist.');
    }
    if (!this.membership.authorize(userId, 'session.join')) {
      throw new MembershipError('PermissionDenied', 'group session access is not permitted.');
    }
    if (session.participants.includes(userId)) {
      return cloneSession(session);
    }
    const updated: GroupSession = {
      ...session,
      participants: [...session.participants, userId]
    };
    this.sessionsById.set(sessionId, updated);
    this.membership.audit.append({
      action: 'session.joined',
      actorId: userId,
      targetId: sessionId,
      at
    });
    return cloneSession(updated);
  }

  sessions(): readonly GroupSession[] {
    return [...this.sessionsById.values()].map(cloneSession);
  }
}
