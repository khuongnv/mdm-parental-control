/// Pure helper computing incremental Realtime device channel lifecycle diffs.
class DeviceChannelDiff {
  final Set<String> toAdd;
  final Set<String> toRemove;
  final Set<String> toKeep;

  const DeviceChannelDiff({
    required this.toAdd,
    required this.toRemove,
    required this.toKeep,
  });
}

DeviceChannelDiff computeDeviceChannelDiff(
  Iterable<String> activeIds,
  Iterable<String> targetIds,
) {
  final active = activeIds.where((id) => id.trim().isNotEmpty).toSet();
  final target = targetIds.where((id) => id.trim().isNotEmpty).toSet();

  final toAdd = target.difference(active);
  final toRemove = active.difference(target);
  final toKeep = active.intersection(target);

  return DeviceChannelDiff(
    toAdd: toAdd,
    toRemove: toRemove,
    toKeep: toKeep,
  );
}
