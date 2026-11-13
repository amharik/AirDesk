import type {
  MergeWorkspaceResult,
  WorkspaceSnapshot
} from './workspace';

export interface WorkspaceSyncCoreBridge {
  mergeSnapshots(localJson: string, remoteJson: string): string;
}

export function mergeWorkspaceSnapshotsWithCore(
  local: WorkspaceSnapshot,
  remote: WorkspaceSnapshot,
  bridge: WorkspaceSyncCoreBridge
): MergeWorkspaceResult {
  const result = bridge.mergeSnapshots(
    JSON.stringify(local),
    JSON.stringify(remote)
  );
  return JSON.parse(result) as MergeWorkspaceResult;
}
