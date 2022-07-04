{
  const locks = db.adminCommand({currentOp: 1, $ownOps: true}).fsyncLock;
  exit(+locks);
}
