import { MembershipError } from './membership';
import type { MemberRole, MembershipStore } from './membership';
import type { AuditLog } from './audit';

export type SharedResourceKind =
  | 'file'
  | 'document'
  | 'database'
  | 'application-data'
  | 'runtime-volume';

export type ResourceAccess = 'none' | 'read' | 'write' | 'manage';

export type ResourcePermission = 'resource.read' | 'resource.write' | 'resource.manage';

const ACCESS_RANK: Record<ResourceAccess, number> = {
  none: 0,
  read: 1,
  write: 2,
  manage: 3
};

const ROLE_ACCESS_CAP: Record<MemberRole, ResourceAccess> = {
  owner: 'manage',
  editor: 'write',
  viewer: 'read'
};

export interface SharedResourcePolicy {
  visibility: 'workspace' | 'private';
  defaultAccess: ResourceAccess;
  memberAccess?: Readonly<Record<string, ResourceAccess>>;
}

export interface SharedResource {
  id: string;
  workspaceId: string;
  kind: SharedResourceKind;
  ownerId: string;
  policy: SharedResourcePolicy;
}

export interface NewSharedResource {
  id: string;
  kind: SharedResourceKind;
  ownerId?: string;
  policy: SharedResourcePolicy;
}

export type ResourceErrorCode = 'ResourceExists' | 'ResourceNotFound' | 'WorkspaceMismatch';

export class ResourceError extends Error {
  readonly code: ResourceErrorCode;

  constructor(code: ResourceErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'ResourceError';
    this.code = code;
  }
}

function minimumAccess(left: ResourceAccess, right: ResourceAccess): ResourceAccess {
  return ACCESS_RANK[left] <= ACCESS_RANK[right] ? left : right;
}

export function resourceAccessFor(
  role: MemberRole,
  resource: SharedResource,
  userId: string
): ResourceAccess {
  if (role === 'owner') return 'manage';

  const roleCap = ROLE_ACCESS_CAP[role];
  if (resource.ownerId === userId) {
    return minimumAccess('manage', roleCap);
  }
  if (resource.policy.visibility === 'private') {
    return 'none';
  }

  const granted = resource.policy.memberAccess?.[userId] ?? resource.policy.defaultAccess;
  return minimumAccess(granted, roleCap);
}

function cloneResource(resource: SharedResource): SharedResource {
  return {
    ...resource,
    policy: {
      ...resource.policy,
      ...(resource.policy.memberAccess
        ? { memberAccess: { ...resource.policy.memberAccess } }
        : {})
    }
  };
}

export class SharedResourceStore {
  private readonly resources = new Map<string, SharedResource>();

  constructor(
    private readonly membership: MembershipStore,
    private readonly auditLog: AuditLog = membership.audit
  ) {}

  add(actorId: string, input: NewSharedResource): SharedResource {
    if (!this.membership.authorize(actorId, 'resource.write')) {
      throw new MembershipError('PermissionDenied', 'resource creation is not permitted.');
    }
    if (this.resources.has(input.id)) {
      throw new ResourceError('ResourceExists', 'shared resource already exists.');
    }
    const resource: SharedResource = {
      id: input.id,
      workspaceId: this.membership.state.workspaceId,
      kind: input.kind,
      ownerId: input.ownerId ?? actorId,
      policy: {
        visibility: input.policy.visibility,
        defaultAccess: input.policy.defaultAccess,
        ...(input.policy.memberAccess
          ? { memberAccess: { ...input.policy.memberAccess } }
          : {})
      }
    };
    this.resources.set(resource.id, resource);
    this.auditLog.append({
      action: 'resource.added',
      actorId,
      targetId: resource.id,
      detail: { kind: resource.kind }
    });
    return cloneResource(resource);
  }

  resource(resourceId: string): SharedResource | null {
    const resource = this.resources.get(resourceId);
    return resource ? cloneResource(resource) : null;
  }

  access(userId: string, resourceId: string): ResourceAccess {
    const resource = this.resources.get(resourceId);
    const role = this.membership.roleOf(userId);
    if (!resource || !role) return 'none';
    return resourceAccessFor(role, resource, userId);
  }

  authorize(userId: string, resourceId: string, permission: ResourcePermission): boolean {
    const required: ResourceAccess =
      permission === 'resource.manage'
        ? 'manage'
        : permission === 'resource.write'
          ? 'write'
          : 'read';
    return ACCESS_RANK[this.access(userId, resourceId)] >= ACCESS_RANK[required];
  }

  setAccess(
    actorId: string,
    resourceId: string,
    userId: string,
    access: ResourceAccess,
    at = Date.now()
  ): SharedResource {
    const resource = this.resources.get(resourceId);
    if (!resource) {
      throw new ResourceError('ResourceNotFound', 'shared resource does not exist.');
    }
    const actorAccess = this.access(actorId, resourceId);
    if (resource.ownerId !== actorId && actorAccess !== 'manage') {
      throw new MembershipError('PermissionDenied', 'resource policy management is not permitted.');
    }
    const memberAccess = {
      ...(resource.policy.memberAccess ?? {}),
      [userId]: access
    };
    const updated: SharedResource = {
      ...resource,
      policy: { ...resource.policy, memberAccess }
    };
    this.resources.set(resourceId, updated);
    this.auditLog.append({
      action: 'resource.access-changed',
      actorId,
      targetId: resourceId,
      at,
      detail: { userId, access }
    });
    return cloneResource(updated);
  }
}
