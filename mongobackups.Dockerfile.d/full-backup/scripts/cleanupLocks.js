{
  const verbose = (process.env.VERBOSE === 'true');
  const locks = db.adminCommand({lockInfo: 1}).lockInfo
                  .filter(resource => resource.granted.some(lock => /^fs/.test(lock.desc)));

  if (verbose)
    console.log(`There are ${locks.length} fslock remaining. Unlocking...`);

  for (let i = 0; i < locks.length; i++) {
    const unlock = db.fsyncUnlock();
    if (verbose)
      console.log(`[${i}]`, unlock);
  }

  if (verbose) {
    const locks = db.adminCommand({lockInfo: 1}).lockInfo
                    .filter(resource => resource.granted.some(lock => /^fs/.test(lock.desc)))
                    .map(resource => { delete resource.pending; return resource; });
    console.log(locks);
  }
}
