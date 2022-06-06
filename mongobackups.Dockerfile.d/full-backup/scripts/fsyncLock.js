{
  const verbose = (process.env.VERBOSE === 'true');

  const result = db.fsyncLock();
  if (verbose)
    console.log(result);
}
