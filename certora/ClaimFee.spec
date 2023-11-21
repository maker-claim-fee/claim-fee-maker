// SPDX-License-Identifier: AGPL-3.0-or-later

using Vat as vat
using Gate1 as gate

////////////////////////////////////////////////////////////////////////////
//                      Methods                                           //
////////////////////////////////////////////////////////////////////////////

methods {

  // ClaimFee contract Envfree methods
  wards(address) returns (uint256) envfree // governance users
  can(address, address) returns (uint256) envfree // approved users
  vat() returns address envfree  // returns vat address stored in claimfee
  gate() returns address envfree // returns gate address stored in claimfee
  initializedIlks(bytes32) returns (bool) envfree // returns true if the ilk is initialized.
  closeTimestamp() returns (uint256) envfree // returns the timestamp at which deco instance was closed.
  latestRateTimestamp(bytes32) returns (uint256) envfree // returns the latest rate timestamp of the given ilk
  cBal(address, bytes32) returns (uint256) envfree // returns the claimBalance of a user for a given ilkclass
  totalSupply(bytes32) returns (uint256) envfree // returns the total supply of claimBalance
  getClass(bytes32, uint256, uint256) returns (bytes32) envfree // returns the class for ilk, iss, maturity
  rate(bytes32, uint256) returns (uint256) envfree // returns the rate value for a ilk at a given timestamp.
  ratio(bytes32, uint256) returns (uint256) envfree // returns the ratio value set for a given class and timestamp.

  // ClaimFee contract methods (connected to env)
  rely(address) // governance add a new ward
  deny(address) // governance removes an existing ward
  hope(address) // user to add a new approver
  nope(address) // user to remove an existing approver
  file(bytes32, address) // set the gate contract address
  initializeIlk(bytes32) // add a new ilk
  snapshot(bytes32) returns (uint256) // record the ilk rate at current timestamp
  moveClaim(address, address, bytes32, uint256) // move claimbalance to another user
  issue(bytes32, address, uint256, uint256, uint256) // governance issues claimbalance
  insert(bytes32, uint256, uint256, uint256) // governance inserts a new rate value
  slice(bytes32, address, uint256, uint256, uint256, uint256) // user slices 1 claimBalance to 2
  merge(bytes32, address, uint256, uint256, uint256, uint256) // user merges 2 claimBalances to 1
  calculate(bytes32, uint256, uint256) // governance stores a ratio value
  collect(bytes32, address, uint256, uint256, uint256, uint256) // user collect yield earned by a claimBalance
  rewind(bytes32, address, uint256, uint256, uint256, uint256) // user rewinds the issuance of claimbalance to past timestamp.
  activate(bytes32, address, uint256, uint256, uint256) // user activates the claimBalance
  close() // governance shutdown the deco instance

  // Gate contract methods
  gate.vat() returns address envfree // returns vat address stored in gate contract
  gate.draw(address, uint256) // draw the dai from vat to usr
  gate.accessSuck(uint256) returns bool

  // Vat contract methods
  vat.ilks(bytes32) returns (uint256, uint256, uint256, uint256, uint256) envfree // returns true if the ilk is initialized in VAT contract (maker)
  vat.live() returns (uint256) // vat live status
  vat.suck(address, address, uint256) // suck dai
  vat.dai(address) returns uint256 // returns dai balance of user in vat
  //vat.move(address, amount) // transfer amount to address
}

////////////////////////////////////////////////////////////////////////////
//                       Rules                                            //
////////////////////////////////////////////////////////////////////////////

/*
  Rule : Assert new ilk added by governance
*/
rule initializeIlk(bytes32 ilk)
description "Verify ilk initialization that allows to claim fee issuance"
{
  env e;

  initializeIlk(e, ilk);

  assert(initializedIlks(ilk) == true, "ilk is NOT initialized in the claimfee maker");
}

/*
   Rule : Verify all the revert riles when adding a new ilk
*/
rule initializeIlk_with_reverts(bytes32 ilkc)
description "Verify to capture all the revert cases that may be exhibited from initializeIlk method"
{
  env e;

  require(e.msg.value == 0);

  uint256 _senderWardStatus = wards(e.msg.sender);
  bool _ilkInitializeStatus = initializedIlks(ilkc);
  uint256 _decoCloseTimestamp = closeTimestamp();

  uint256 _art; uint256 _rate; uint256 _spot; uint256 _line; uint256 _dust;
  _art, _rate, _spot, _line, _dust = vat.ilks(ilkc);

  initializeIlk@withrevert(e, ilkc);

  bool initializeReverted = lastReverted;

  bool revert1 = _senderWardStatus != 1;
  bool revert2 = e.msg.value != 0;
  bool revert3 = _ilkInitializeStatus;
  bool revert4 = e.block.timestamp >= _decoCloseTimestamp;
  bool revert5 = _rate == 0;

  assert ( revert1 => initializeReverted, "the sender is not authorized to initialize ILK, but the method did not revert");
  assert ( revert2 => initializeReverted, "the initializeIlk function do not accept any payment");
  assert ( revert3 => initializeReverted, "the ilk is already initialized but the function did not revert");
  assert ( revert4 => initializeReverted, "cannot initialize ILK after the deco instance is closed, but the function did not revert");
  assert ( revert5 => initializeReverted, "Ilk is not initialized in VAT, but the 'initialize' function did not revert");

  assert ( initializeReverted => revert1 || revert2 || revert3 || revert4 || revert5, "Failed to capture all reverts, All the revert conditions were not identified in the initializeILK method");

}

/*
  Rule : Assert the recorded ilk rate at a given timestamp.
*/
rule snapshot(bytes32 ilk)
description "Snapshot the ilk rate value (in vat) at current block timestamp"
{
  env e;

  uint256 _art; uint256 _rate; uint256 _spot; uint256 _line; uint256 _dust;
  _art, _rate, _spot, _line, _dust = vat.ilks(ilk);

  uint256 snapshotRate = snapshot(e, ilk);

  assert(_rate == snapshotRate, "The rate recorded for ilk snapshot is different from the vat");

}

/*
  Rule : Verify all the revert rules when recording ilk rate at block timestamp.
*/
rule snapshot_with_reverts(bytes32 ilk)
description "Capture all the revert paths from the 'snapshot' function"
{
  env e;

  uint256 _decoCloseTimestamp = closeTimestamp();
  bool _ilkInitializeStatus = initializedIlks(ilk);

  uint256 _art; uint256 _rate; uint256 _spot; uint256 _line; uint256 _dust;
  _art, _rate, _spot, _line, _dust = vat.ilks(ilk);

  snapshot@withrevert(e, ilk);

  bool snapshotReverted = lastReverted;

  bool revert1 = e.block.timestamp >= _decoCloseTimestamp;
  bool revert2 = !_ilkInitializeStatus;
  bool revert3 = e.msg.value != 0;

  assert(revert1 => snapshotReverted, "the current timestamp is past deco instance closets, but the snapshot function did not revert");
  assert(revert2 => snapshotReverted, "the ilk is not initialized and hence cannot take snapshot, but the snapshot function did not revert");
  assert(revert3 => snapshotReverted, "the snapshot method MUST not accept any ETH");

  assert(snapshotReverted => revert1 || revert2 || revert3 , "Failed to capture all reverts, All the reverts from the function 'snapshot' was not captured");
}

/*
  Rule : Assert the balances when a user moves claimBalance to other.
*/
rule moveclaim(address src, address dst, bytes32 class, uint256 balanceAmount)
description "Transfer a user claimBalance to another user"
{
  env e;

  uint256 _senderClaimBalance = cBal(src, class);
  uint256 _destClaimBalance = cBal(dst, class);

  moveClaim(e, src, dst, class, balanceAmount);

  uint256 senderClaimBalance_ = cBal(src, class);
  uint256 destClaimBalance_ = cBal(dst, class);

  assert(src != dst => _senderClaimBalance == senderClaimBalance_ + balanceAmount && destClaimBalance_ == _destClaimBalance + balanceAmount, "Sender and Receiver balances are adjusted by transferamount");
  assert(src == dst => _senderClaimBalance == destClaimBalance_, "sender is same as receiver, balance do not change");

}

/*
  Rule : Verify all the revert rules when a user moves their claim balance to other.
*/
rule moveClaim_with_reverts(address src, address dst, bytes32 class, uint256 balanceAmount) {

  env e;

  uint256 _srcBalance = cBal(src, class);
  uint256 _dstBalance = cBal(dst, class); // for debugging purpose only

  require (_dstBalance + balanceAmount < max_uint, "receiver balance integer overflow"); // scope integer overflow

  moveClaim@withrevert(e, src, dst, class, balanceAmount);
  bool moveClaimReverted = lastReverted;
  uint256 approvalStatus = can(src, e.msg.sender);

  require (approvalStatus == 1 || approvalStatus == 0, "Eliminate invalid approver status values");

  bool revert1 = e.msg.value != 0;
  bool revert2 = _srcBalance < balanceAmount;
  bool revert3 = e.msg.sender != src && approvalStatus != 1;

  assert(revert1 => moveClaimReverted, "moveClaim cannot accept ETH");
  assert(revert2 => moveClaimReverted, "sender do not have sufficient balance, but the moveClaim function did not revert");
  assert(revert3 => moveClaimReverted, "the message sender is not approved from the source, but the moveClaim function did not revert");

  assert(moveClaimReverted => revert1 || revert2 || revert3, "Failed to capture all reverts, All the possible reverts of 'moveClaim' function were not captured");
}

/*
  Rule : Verify that governance can issue ClaimBalance
*/
rule issue(bytes32 ilk, address usr, uint256 iss, uint256 mat, uint256 balanceAmount)
description "Issue claimbalance to user"
{
  env e;

  bytes32 class = getClass(ilk, iss, mat);
  uint256 _usrBal = cBal(usr, class);
  uint256 _totalSupply = totalSupply(class);

  issue(e, ilk, usr, iss, mat, balanceAmount);

  uint256 usrBal_ = cBal(usr, class);
  uint256 totalSupply_ = totalSupply(class);

  assert(usrBal_ == _usrBal + balanceAmount, "The usr claimBalance did not increase");
  assert(totalSupply_ == _totalSupply + balanceAmount, "The totalsupply of the class did not increase");
}

/*
  Rule : Verify all the reverts for issue. A governance can issue claimBalance as long as the deco instance is active.
*/
rule issue_with_reverts(bytes32 ilk, address usr, uint256 iss, uint256 mat, uint256 balanceAmount)
description "Verify to capture all the possible reverts from the issue function"
{

  env e;

  uint256 _latestRatetimestamp = latestRateTimestamp(ilk);
  uint256 _currentTimestamp = e.block.timestamp;
  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 _issRate = rate(ilk, iss);
  uint256 _decoCloseTimestamp = closeTimestamp();
  bool _ilkInitializeStatus = initializedIlks(ilk);
  bytes32 class = getClass(ilk, iss, mat);

  require (totalSupply(class) + balanceAmount < max_uint, "totalsupply overflow");
  require (cBal(usr, class) + balanceAmount < max_uint, "user's claimbalance overflow");

  issue@withrevert(e, ilk, usr, iss, mat, balanceAmount);

  bool issueReverted = lastReverted;

  bool revert1 = e.msg.value != 0;
  bool revert2 = iss > _latestRatetimestamp || mat < _currentTimestamp;
  bool revert3 = _senderWardStatus != 1;
  bool revert4 = _issRate == 0;
  bool revert5 = _currentTimestamp >= _decoCloseTimestamp;
  bool revert6 = !_ilkInitializeStatus;

  assert(revert1 => issueReverted, "issue cannot accept ETH");
  assert(revert2 => issueReverted, "issuance has to be before or latest, maturity cannot be before current block ts");
  assert(revert3 => issueReverted, "the sender is not authorized to issue claim balance, but the method did not revert");
  assert(revert4 => issueReverted, "the rate value at issuance doesn't exist, but the function did not revert");
  assert(revert5 => issueReverted, "cannot issue claimbalance after the deco instance is closed, but the function did not revert");
  assert(revert6 => issueReverted, "the ilk must be initialized before issuing claim balance");

  assert(issueReverted => revert1 || revert2 || revert3 || revert4 || revert5 || revert6, "Failed to catch all the possible reverts from the 'issue' function ");

}
/*
  Rule : A governance user can withdraw their claim balance
*/
rule withdraw(bytes32 ilk, address usr, uint256 iss, uint256 mat, uint256 balanceAmount)
description "An authorized user can withdraw the claimbalance"
{
  env e;

  bytes32 class = getClass(ilk, iss, mat);
  uint256 _senderClaimBalance = cBal(usr, class);
  uint256 _totalSupply = totalSupply(class);

  withdraw(e, ilk, usr, iss, mat, balanceAmount);

  uint256 senderClaimBalance_ = cBal(usr, class);
  uint256 totalSupply_ = totalSupply(class);

  assert(senderClaimBalance_ == _senderClaimBalance - balanceAmount, "Sender balances are adjusted by transferamount");
  assert(totalSupply_ == _totalSupply - balanceAmount , "sender is same as receiver, balance do not change");

}

/*
  Rule : Verify all the reverts when a governance can withdraw a claimbalance.
         A regular user cannot withdraw their own balance.
*/
rule withdraw_with_reverts(bytes32 ilk, address usr, uint256 iss, uint256 mat, uint256 balanceAmount)
description "Verify all the possible reverts from the withdraw function"
{
  env e;

  bytes32 class = getClass(ilk, iss, mat);
  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 _usrBal = cBal(usr, class);
  uint256 _totalSupply = totalSupply(class);

  withdraw@withrevert(e, ilk, usr, iss, mat, balanceAmount);

  bool withdrawReverted = lastReverted;

  bool revert1 = e.msg.value != 0;
  bool revert2 = _senderWardStatus != 1;
  bool revert3 = _usrBal < balanceAmount;
  bool revert4 = _totalSupply < balanceAmount;

  assert(revert1 => withdrawReverted, "withdraw function cannot accept any ETH");
  assert(revert2 => withdrawReverted, "the sender is not authorized to withdraw user claimbalance");
  assert(revert3 => withdrawReverted, "the user do not have sufficient balance to be withdrawn");
  assert(revert4 => withdrawReverted, "the totalsupply is less than the requested claimbalance");

  assert( withdrawReverted => revert1 || revert2 || revert3 || revert4, "Failed to catch all the possible reverts from the 'withdraw' function");

}
/*
  Rule : Verify that goveernance can set the rate value at a given timestamp.
*/
rule insert(bytes32 ilk, uint256 tBefore, uint256 t, uint256 rateval)
description "Verify that governance can insert a rate at a timestamp"
{
  env e;

  // latest rate val
  uint256 _latestRateTs = latestRateTimestamp(ilk);
  uint256 _latestRateVal = rate(ilk, _latestRateTs);

  // before rate val
  uint256 _beforeRateVal = rate(ilk, tBefore);

  insert(e, ilk, tBefore, t, rateval);

  assert(rate(ilk, t) == rateval && rateval != 0, "Failed to set the rate at given timestamp");
  assert(rateval >= _beforeRateVal && rateval <= _latestRateVal, "the new inserted rate should fall between the before and latest ");
}

/*
  Rule : Verify all the revert rules when a governance can insert a rate value
*/
rule insert_with_reverts(bytes32 ilk, uint256 tBefore, uint256 t, uint256 rateval)
description "CVL verify all the possible reverts from the insert rate function"
{
  env e;

  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 tLatest = latestRateTimestamp(ilk);
  uint256 RAY = 10 ^ 27;
  uint256 _curRateVal = rate(ilk, t);
  uint256 _beforeRateVal = rate(ilk, tBefore);
  uint256 _latestRateVal = rate(ilk, tLatest);

  insert@withrevert(e, ilk, tBefore, t, rateval);

  bool insertReverted = lastReverted;

  bool revert1 = e.msg.value != 0;
  bool revert2 = _senderWardStatus != 1;
  bool revert3 = t <= tBefore || t >= tLatest;
  bool revert4 = rateval < RAY;
  bool revert5 = _curRateVal != 0;
  bool revert6 = rateval < _beforeRateVal || rateval > _latestRateVal;
  bool revert7 = _beforeRateVal == 0;

  assert(revert1 => insertReverted, "inserting rate function do not accept any ETH");
  assert(revert2 => insertReverted, "sender is not authorized to set rate, but the functino did not revert");
  assert(revert3 => insertReverted, "the timestamp for rateinsert should be between before and the latest ts recorded");
  assert(revert4 => insertReverted, "the rate value cannot be less than 1 RAY");
  assert(revert5 => insertReverted, "the rate val is already present at t, cannot override");
  assert(revert6 => insertReverted, "the rate should lie between rate at tbefore and the latest ratetimestamp recorded");
  assert(revert7 => insertReverted, "the previous rate is not recorded, but the function did not revert");

  assert(insertReverted => revert1 || revert2 || revert3 || revert4 || revert5 || revert6 || revert7, "Failed to identify all the reverts from the 'insert' function");

}

/*
  Rule : Verify that slice method splits the claimbalance into two balances at a given timestamp.
  The input claimBalance will be burnt, and two new claimBalances will be mint.
*/
rule slice(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 balanceAmount)
description "A user's claimbalance is sliced into two claimbalances at a given slice timestamp"
{

  env e;

  // T1-T3
  bytes32 class_t1t3 = getClass(ilk, t1, t3);
  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);

  // T1-T2
  bytes32 class_t1t2 = getClass(ilk, t1, t2);
  uint256 _usrBal_t1t2 = cBal(usr, class_t1t2);

  // T2-T3
  bytes32 class_t2t3 = getClass(ilk, t2, t3);
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);

  slice(e, ilk, usr, t1, t2, t3, balanceAmount); // slice the claimbalance

  uint256 usrBal_t1t2_ = cBal(usr, class_t1t2);
  uint256 usrBal_t2t3_ = cBal(usr, class_t2t3);
  uint256 usrBal_t1t3_ = cBal(usr, class_t1t3);

  assert(usrBal_t1t3_ == _usrBal_t1t3 - balanceAmount, "T1T3 -original claim balance was not reduced");
  assert(usrBal_t1t2_ == _usrBal_t1t2 + balanceAmount, "T1T2 - user's split claim balance was not increased");
  assert(usrBal_t2t3_ == _usrBal_t2t3 + balanceAmount, "T2T3 - user's split claim balance was not increased");

}

/*
  Rule : Verify all the revert rules when a claimbalance is split in to two. The user balances are thus adjusted accordingly.
*/
rule slice_with_revert(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 balanceAmount)
description "all the possible reverts from the slice function"
{
  env e;

  bytes32 class_t1t3 = getClass(ilk, t1, t3);
  bytes32 class_t1t2 = getClass(ilk, t1, t2);
  bytes32 class_t2t3 = getClass(ilk, t2, t3);
  uint256 _totalSupply_t1t3 = totalSupply(class_t1t3);
  uint256 _totalSupply_t2t3 = totalSupply(class_t2t3);
  uint256 _totalSupply_t1t2 = totalSupply(class_t1t2);

  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);
  uint256 _usrBal_t1t2 = cBal(usr, class_t1t2);
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);

  bool ilkStatus = initializedIlks(ilk);
  bool approverStatus = (usr == e.msg.sender) || can(usr, e.msg.sender) == 1;

  require (_totalSupply_t2t3 + balanceAmount < max_uint, "t2t3 totalsupply overflow");
  require (_totalSupply_t1t2 + balanceAmount < max_uint, "t1t2 totalsupply overflow");
  require (_usrBal_t1t2 + balanceAmount < max_uint, "user balance overflow");
  require (_usrBal_t2t3 + balanceAmount < max_uint, "user balance overflow");

  slice@withrevert(e, ilk, usr, t1, t2, t3, balanceAmount); // slice the claimbalance

  bool sliceReverted = lastReverted;

  bool revert1 = e.msg.value != 0;
  bool revert2 = t1 >= t2 || t2 >= t3;
  bool revert3 = _usrBal_t1t3 < balanceAmount;
  bool revert4 = !ilkStatus;
  bool revert5 = _totalSupply_t1t3 < balanceAmount;
  bool revert6 = !approverStatus;

  assert(revert1 => sliceReverted, "slice function will not accept ETH");
  assert(revert2 => sliceReverted, "the slice timestamp is outside the range");
  assert(revert3 => sliceReverted, "user do not have sufficient balance,  slice failed to revert");
  assert(revert4 => sliceReverted, "ilk is not initialized in maker vat, slice failed to revert");
  assert(revert5 => sliceReverted, "total supply is less than the requested claimbalance");
  assert(revert6 => sliceReverted, "sender is not approved to slice claimbalance");

  assert(sliceReverted => revert1 || revert2 || revert3 || revert4 || revert5 || revert6, "Failed to cover all the possible reverts from the slice function");

}

/*
  Rule : Verify the process of merging claimbalances. The claimbalances should be adjusted accordingly.
*/
rule merge(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 balanceAmount)
description "Verify that merge two claims with continuous time periods into one claim balance"
{
  env e;

  // T1-T2
  bytes32 class_t1t2 = getClass(ilk, t1, t2);
  uint256 _usrBal_t1t2 = cBal(usr, class_t1t2);

  // T2-T3
  bytes32 class_t2t3 = getClass(ilk, t2, t3);
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);

  // T1-T3
  bytes32 class_t1t3 = getClass(ilk, t1, t3);
  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);

  merge(e, ilk, usr, t1, t2, t3, balanceAmount); // merge the adjacent claimbalances

  uint256 usrBal_t1t2_ = cBal(usr, class_t1t2);
  uint256 usrBal_t2t3_ = cBal(usr, class_t2t3);
  uint256 usrBal_t1t3_ = cBal(usr, class_t1t3);

  assert(usrBal_t1t3_ == _usrBal_t1t3 + balanceAmount, "T1T3 - merged claim balance is minted");
  assert(usrBal_t1t2_ == _usrBal_t1t2 - balanceAmount, "T1T2 - user's split claim balance is burned");
  assert(usrBal_t2t3_ == _usrBal_t2t3 - balanceAmount, "T2T3 - user's split claim balance is burned");

}

/*
  Rule : Verify all the revert rules upon merging two claim balances to single claim balance
*/
rule merge_with_reverts(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 balanceAmount)
description "all possible reverts from the merge function"
{
  env e;

  // class - hashes
  bytes32 class_t1t3 = getClass(ilk, t1, t3);
  bytes32 class_t1t2 = getClass(ilk, t1, t2);
  bytes32 class_t2t3 = getClass(ilk, t2, t3);
  // claimBalances
  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);
  uint256 _usrBal_t1t2 = cBal(usr, class_t1t2);
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);
  // total supply
  uint256 _totalSupply_t1t3 = totalSupply(class_t1t3);
  uint256 _totalSupply_t2t3 = totalSupply(class_t2t3);
  uint256 _totalSupply_t1t2 = totalSupply(class_t1t2);

  bool ilkStatus = initializedIlks(ilk);
  bool approverStatus = (usr == e.msg.sender) || can(usr, e.msg.sender) == 1;

  require (_totalSupply_t1t3 + balanceAmount < max_uint, "t1t3 totalsupply overflow");
  require (_usrBal_t1t3 + balanceAmount < max_uint, "user balance overflow");

  merge@withrevert(e,ilk, usr, t1, t2, t3, balanceAmount);

  bool mergeReverted = lastReverted; // lastReverted is a CVL standard var that holds status of revert

  bool revert1 = e.msg.value != 0;
  bool revert2 = t1 >= t2 || t2 >= t3;
  bool revert3 = _usrBal_t1t2 < balanceAmount;
  bool revert4 = _usrBal_t2t3 < balanceAmount;
  bool revert5 = !ilkStatus;
  bool revert6 = !approverStatus;
  bool revert7 = _totalSupply_t1t2 < balanceAmount || _totalSupply_t2t3 < balanceAmount;

  assert(revert1 => mergeReverted, "merge function do not accept any ETH");
  assert(revert2 => mergeReverted, "merge timestamps must be adjacent");
  assert(revert3 => mergeReverted, "user has insufficient t1t2 balance");
  assert(revert4 => mergeReverted, "user has insufficient t2t3 balance");
  assert(revert5 => mergeReverted, "merge cannot be performed if ilk is not initialized");
  assert(revert6 => mergeReverted, "sender is not approved to invoke merge function");
  assert(revert7 => mergeReverted, "total supply of claimbalances are insufficient");

  assert(mergeReverted => revert1 || revert2 || revert3 || revert4 || revert5 || revert6 || revert7 , "Failed to capture all the reverts from merge function");
}

/*
  Rule : Verify that if ratio value is set correctly for a given ilk.
*/
rule calculate(bytes32 ilk, uint256 mat, uint256 ratio)
description "set ratio value for ilk at maturity ts"
{
  env e;

  calculate(e, ilk, mat, ratio);

  assert(ratio(ilk, mat) == ratio, "Failed to set ratio value");

}

/*
  Rule : Verify all the reverts rules while setting the ratio value for ilk.
*/
rule calculate_with_revert(bytes32 ilk, uint256 mat, uint256 ratio)
description "verify all the reverts of calculate"
{
  env e;

  uint256 ratioVal = ratio(ilk, mat);
  uint256 WAD = 10 ^ 18;
  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 _decoCloseTimestamp = closeTimestamp();

  calculate@withrevert(e, ilk, mat, ratio);

  bool calculateReverted = lastReverted;
  bool revert1 = ratioVal != 0;
  bool revert2 = e.msg.value != 0;
  bool revert3 = ratio > WAD;
  bool revert4 = _senderWardStatus != 1;
  bool revert5 = e.block.timestamp < _decoCloseTimestamp;

  assert(revert1 => calculateReverted, "overwriting of ratio value is not permitted");
  assert(revert2 => calculateReverted, "method do not accept any ETH");
  assert(revert3 => calculateReverted, "invalid ratio, need to be less than or equal to 1");
  assert(revert4 => calculateReverted, "sender is not authorized");
  assert(revert5 => calculateReverted, "cannot set ratio after close");

  assert( calculateReverted => revert1 || revert2 || revert3 || revert4 || revert5, "Failed to capture all reverts in calculate function");

}

/*
  Rule : Verify the deco instance shutdown.
*/
rule close()
description "Verify the deco instance closure"
{
  env e;

  uint256 _decoCloseTs = e.block.timestamp;

  close(e);

  assert(closeTimestamp() == _decoCloseTs, "Failed to set deco close timestamp");
}

/*
  Rule : Verify all the reverts captured during shutdown of deco instance.
*/
rule close_with_revert()
description "Verify all the reverts from the close function"
{
  env e;

  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 _decoCloseTs = closeTimestamp();
  uint256 _vatLive = vat.live(e);

  close@withrevert(e);

  bool closeReverted = lastReverted;

  bool revert1 = _senderWardStatus != 1 && vat.live(e) != 0;
  bool revert2 = _decoCloseTs != max_uint;

  assert(revert1 => closeReverted, "The sender is not authorized to close deco instance");
  assert(revert2 => closeReverted, "The closets is already set for deco instance");

  assert(closeReverted => revert1 || revert2, "Failed to capture all the revert conditions from close method");

}

/*
  Rule : Verify if user can activate claimBalance and thus the claimBalance gets adjusted accordingly.
*/
rule activate(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 bal)
description "Activate claimbalance whose issuance timestamp does not have a rate value set"
{

  env e;

  bytes32 class_t1t3 = getClass(ilk, t1, t3); // t1 -> Issuance TS(without rate), t3 -> Maturity TS
  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);

  bytes32 class_t2t3 = getClass(ilk, t2, t3); // t2 -> Activation TS (with rate), t3 -> Maturity TS
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);

  activate(e, ilk, usr, t1, t2, t3, bal);

  uint256 usrBal_t1t3_ = cBal(usr, class_t1t3);
  uint256 usrBal_t2t3_ = cBal(usr, class_t2t3);

  assert(usrBal_t1t3_ == _usrBal_t1t3 - bal, "The inactive claimbalance (without rate) was not adjusted");
  assert(usrBal_t2t3_ == _usrBal_t2t3 + bal, "The active claimbalance (with rate) was not adjusted correctly");

}

/*
  Rule : Verify all the reverts when a user activates claimbalance
*/
rule activate_with_reverts(bytes32 ilk, address usr, uint256 t1, uint256 t2, uint256 t3, uint256 bal)
description "Verify the reverts from activate function"
{
  env e;

  bool approverStatus = (usr == e.msg.sender) || can(usr, e.msg.sender) == 1;

  bytes32 class_t1t3 = getClass(ilk, t1, t3); // t1 -> Issuance TS(without rate), t3 -> Maturity TS
  uint256 _usrBal_t1t3 = cBal(usr, class_t1t3);

  bytes32 class_t2t3 = getClass(ilk, t2, t3); // t2 -> Activation TS (with rate), t3 -> Maturity TS
  uint256 _usrBal_t2t3 = cBal(usr, class_t2t3);

  uint256 _totalSupply_t1t3 = totalSupply(class_t1t3);

  require(totalSupply(class_t2t3) + bal < max_uint, "total supply overflow");
  require(_usrBal_t2t3 + bal < max_uint, "user claimbalance overflow");

  activate@withrevert(e, ilk, usr, t1, t2, t3, bal);

  bool activateReverted = lastReverted;

  bool revert1 = !approverStatus;
  bool revert2 = t1 >= t2 || t2 >= t3;
  bool revert3 = rate(ilk,t1) != 0;
  bool revert4 = rate(ilk,t2) == 0;
  bool revert5 = _usrBal_t1t3 < bal;
  bool revert6 = !initializedIlks(ilk);
  bool revert7 = e.msg.value != 0;
  bool revert8 = _totalSupply_t1t3 < bal;

  assert(revert1 => activateReverted, "the sender is not authorized to activate the claimbalance");
  assert(revert2 => activateReverted, "the activation timestamps are invalid");
  assert(revert3 => activateReverted, "the rate at issuance must not be set");
  assert(revert4 => activateReverted, "the rate at activation must be set");
  assert(revert5 => activateReverted, "the user issuance claimbalance is insufficient");
  assert(revert6 => activateReverted, "the ilk must be initialized");
  assert(revert7 => activateReverted, "the activate method do not accept ETH");
  assert(revert8 => activateReverted, "the claimbalance of user is insufficient to burn");

  assert(activateReverted => revert1 || revert2 || revert3 || revert4 || revert5 || revert6 || revert7 || revert8 , "Failed to catch all the possible reverts from the activate function");

}

/*
 Rule : Verify that method 'deny' works as expected,
 An existing ward will be removed. The value of ward will be set to 0.
*/
rule deny(address usr)
description "Verify that method 'deny' works as expected for user : ${usr}"
{
  env e;

  deny(e, usr);

  assert(wards(usr) == 0, "deny did not remove admin from claimfee maker as expected");

}

/*
 Rule : Verify that method 'deny' reverts when sender is not authorized
*/
rule deny_with_revert(address usr)
description "Verify that the method 'deny' reverts when user ${msg.sender} is not authorized"
{

  env e;

  uint256 _senderWardStatus = wards(e.msg.sender);
  uint256 _userWardStatus = wards(usr);

  require(e.msg.value == 0, "cannot accept any eth");

  deny@withrevert(e, usr);

  assert(_senderWardStatus != 1 => lastReverted,  "the sender is unauthorized to perform deny operation");
}

/*
 Rule : Verify that method 'rely' works as expected.
 A new ward will be set.
*/
rule rely(address usr)
description "Verify that method 'rely' works as expected for user : ${usr}"
{
  env e;

  rely(e, usr);

  assert(wards(usr) == 1, "rely did not add admin to claimfee maker as expected");

}

/*
 Rule : Verify that method 'rely' reverts when sender is not authorized.
 Only a ward (aka governance) can add yet another ward.
*/
rule rely_with_revert(address usr)
description "Verify that the method 'rely' reverts when user ${msg.sender} is not authorized"
{
  env e;

  uint256 _wardStatus = wards(e.msg.sender);

  rely@withrevert(e, usr);

  assert(_wardStatus != 1 => lastReverted, "Rely did not revert when user is unauthorized");

}

/*
  Rule : Verify that method 'hope' works as expected.
  A user may add someone as an approver.
*/
rule hope(address usr)
description "Verify that method 'hope' works as expected for user : ${usr}"
{
  env e;

  hope(e, usr);

  assert(can(e.msg.sender, usr) == 1, "hope did not add approver for the user in claimfee maker as expected");

}

/*
  Rule : Verify that method 'nope' works as expected.
  A user may remove someone as an approver.
*/
rule nope(address usr)
description "Verify that method 'nope' works as expected for user : ${usr}"
{
  env e;

  nope(e, usr);

  assert(can(e.msg.sender, usr) == 0, "nope did not remove approver for the user in claimfee maker as expected");

}

/*
  Rule : Verify if the 'gate' address can be updated as expected.
*/
rule file(bytes32 what, address data)
description "Verify that if can update the dss-gate address"
{
  env e;

  file(e, what, data);

  assert(gate() == data, "the gate address was not set correctly");
}

/*
  Rule : Verify the the file method reverts as expected.
*/
rule file_with_revert(bytes32 what, address data)
description "Verify to capture all the possible reverts from the file method"
{
  env e;

  require(data == gate, "the address of gate is not correct");

  uint256 _senderWardStatus = wards(e.msg.sender);

  address _vatAddressInCFM = vat();
  address _vatAddressInGate = gate.vat();
  //require(_vatAddressInCFM == _vatAddressInGate);

  file@withrevert(e, what, data);

  bool revert1 = _senderWardStatus != 1;
  // 0x6761746500000000000000000000000000000000000000000000000000000000 = "gate"
  bool revert2 = what != 0x6761746500000000000000000000000000000000000000000000000000000000;
  bool revert3 = e.msg.value != 0;
  bool revert4 = _vatAddressInCFM != _vatAddressInGate;

  assert ( revert1 => lastReverted, "Sender not authorized, and hence cannot update the gate address");
  assert ( revert2 => lastReverted, "The config key MUST be 'gate' only");
  assert ( revert3 => lastReverted, "This function do not accept any ETH");

}