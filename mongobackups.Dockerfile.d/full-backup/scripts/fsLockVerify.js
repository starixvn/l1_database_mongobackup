{
  const verbose = (process.env.VERBOSE === 'true');
  const locks = db.adminCommand({currentOp: 1, $ownOps: true});

  if (verbose)
    console.log((({fsyncLock, info}) => ({fsyncLock, info}))(locks));

  exit(+locks.fsyncLock);
}
