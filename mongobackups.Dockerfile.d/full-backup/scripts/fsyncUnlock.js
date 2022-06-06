{
  const verbose = (process.env.VERBOSE === 'true');

  const result = db.fsyncUnlock();
  if (verbose)
    console.log(result);
}
