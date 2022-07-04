{
  const dbPath = db.adminCommand({getCmdLineOpts: 1}).parsed.storage.dbPath;
  exit(+(dbPath !== process.env.DATA_PATH));
}
