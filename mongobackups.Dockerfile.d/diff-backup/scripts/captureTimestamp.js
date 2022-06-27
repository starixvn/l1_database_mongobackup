{
  fs.writeFileSync(`${process.env.BACKUP_FULLPATH}.ts`, Math.ceil(ISODate() / 1000).toString());
}
