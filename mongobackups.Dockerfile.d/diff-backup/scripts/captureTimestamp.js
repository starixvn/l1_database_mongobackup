{
  const ts = db.adminCommand({replSetGetStatus: 1}).optimes.appliedOpTime.ts
  fs.writeFileSync(`${process.env.BACKUP_FULLPATH}.ts`, String(ts.getHighBitsUnsigned()));
}
