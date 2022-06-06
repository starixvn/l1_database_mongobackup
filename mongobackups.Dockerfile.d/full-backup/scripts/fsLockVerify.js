{
  const verbose = (process.env.VERBOSE === 'true');
  const locks = db.adminCommand({lockInfo: 1}).lockInfo
                  .filter(resource => resource.granted.some(lock => /^fs/.test(lock.desc)))
                  .map(resource => { delete resource.pending; return resource; });

  if (verbose)
    console.log(locks);

  exit(locks.length);
}
