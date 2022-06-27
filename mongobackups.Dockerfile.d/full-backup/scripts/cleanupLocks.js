{
  const verbose = (process.env.VERBOSE === 'true');
  let locks = db.adminCommand({currentOp: 1, $ownOps: true}).fsyncLock;

  if (verbose)
    console.log(`There are fslock remaining. Unlocking...`);

  let i = 1;
  while (locks) {
    const unlock = db.fsyncUnlock();
    if (verbose)
      console.log(`[${i++}]`, unlock);
    locks = db.adminCommand({currentOp: 1, $ownOps: true}).fsyncLock;
  }

  if (verbose) {
    const locks = db.adminCommand({currentOp: 1, $ownOps: true});
    console.log((({fsyncLock, info}) => ({fsyncLock, info}))(locks));
  }
}
