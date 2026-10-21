// Filenames retain recording-start order even if audio IPC arrives out of order.
// Legacy backup_<savedAt>.webm files have no recording ID and use savedAt.
function backupOrder(filename) {
  const match = /^backup_(\d+)(?:-(\d+)-(\d+)|-[\w-]+)?\.webm$/.exec(filename);
  return match ? [Number(match[2] || match[1]), Number(match[3] || 0)] : null;
}
function compareBackups(firstFilename, secondFilename) {
  const first = backupOrder(firstFilename);
  const second = backupOrder(secondFilename);
  if (!first || !second) return null;
  return first[0] - second[0] || first[1] - second[1];
}
function isBackupAtOrBefore(filename, completedFilename) {
  const order = compareBackups(filename, completedFilename);
  return order !== null && order <= 0;
}
module.exports = { isBackupAtOrBefore, compareBackups };
