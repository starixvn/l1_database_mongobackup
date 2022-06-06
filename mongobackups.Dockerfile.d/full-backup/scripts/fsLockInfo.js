{
  const locks = db.adminCommand({lockInfo: 1}).lockInfo;
  exit(locks.filter(resource => resource.granted.some(lock => /^fs/.test(lock.desc))).length);
}
