{
  const stallLimit = db.getSiblingDB('local').oplog.rs
                      .findOne({}, {}, {sort: {$natural: 1}})
                      .ts.getHighBitsUnsigned();
  if (process.env.TIMESTAMP < stallLimit) {
    fs.writeFileSync(`/tmp/stallLimit`, (stallLimit).toString());
    exit(stallLimit);
  }
}
