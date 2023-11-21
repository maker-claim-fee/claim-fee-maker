// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {ClaimFee} from "../src/ClaimFee.sol";
import {Gate1} from "./deps/gate1.sol";
import "./deps/vat.sol";
import "./deps/DSMath.sol";
import "./deps/Vm.sol";

// Echidna test helper contracts
import "./MockVow.sol";
import "./TestVat.sol";
import "./TestGovUser.sol";
import "./TestMakerUser.sol";
import "./TestClaimHolder.sol";
import "./TestUtil.sol";

/**
    The following Echidna tests focuses on mostly ALL types of asserts :

    1. access control related asserts ( verifying access related)
    2. conditional asserts ( verifying against require conditions)
    3. functional asserts ( verifying business logic)

    Echidna will run a sequence of random input and various call sequences (based on configured depth) to violate the
    access control invariants defined.

 */
contract ClaimFeeEchidnaInvariantTest is DSMath {

    Vm public vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 t0;
    uint256 t1;
    uint256 t2;
    uint256 t3;
    uint256 t4;

    ClaimFee public cfm; // contract to be tested

    TestVat public vat;
    MockVow public vow;
    Gate1 public gate;
    CHolder public holder;
    TestUtil public test_util;

    GovernanceUser public gov_user;
    MakerUser public usr;
    address public me;
    address public gov_addr;
    address public usr_addr;
    address public usr2_addr;
    address public holder_addr;

    MakerUser public usr2;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    bytes32 public ethA_t0_t2_class = keccak256(abi.encodePacked(ETH_A, t0, t2));
    bytes32 public ETH_A = bytes32("ETH-A");
    bytes32 public WBTC_A = bytes32("WBTC-A");
    bytes32 public ETH_Z = bytes32("ETH-Z");

    constructor()  {
        vm.warp(1641400537);

        t0 = block.timestamp; // Current block timestamp
        t1 = block.timestamp + 5 days; // Current block TS + 5 days
        t2 = block.timestamp + 10 days; // Current block TS + 10 days
        t3 = block.timestamp + 15 days; // Current block TS + 15 days
        t4 = block.timestamp + 20 days; // Current block TS + 20 days

        me = address(this);
        vat = new TestVat();
        test_util = new TestUtil();
        vat.rely(address(vat));
        vow = new MockVow(address(vat));
        gate = new Gate1(address(vow));
        vat.rely(address(gate));
        gate.file("approvedtotal", test_util.rad(10000)); // set draw limit

        // claimfee
        cfm = new ClaimFee(address(gate));
        gov_user = new GovernanceUser(cfm);
        gov_addr = address(gov_user);
        cfm.rely(gov_addr); // Add gov user as a ward.
        gate.kiss(address(cfm)); // Add a CFM as integration to gate

        // Public User
        usr = new MakerUser(cfm);
        usr_addr = address(usr);

        usr2 = new MakerUser(cfm);
        usr2_addr = address(usr2);

        vat.ilkSetup(ETH_A); // vat initializes ILK (ETH_A).
        gov_user.initializeIlk(ETH_A); // Gov initializes ILK (ETH_A) in Claimfee as gov is a ward
        vat.ilkSetup(WBTC_A); // Vat initializes ILK (WBTC_A)
        gov_user.initializeIlk(WBTC_A); // gov initialize ILK (WBTC_A) in claimfee as gov is a ward

        vat.increaseRate(ETH_A, test_util.wad(5), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.05

    }

    // Access Invariant - ilk cannot be initialized by a regular user
    function test_ilk_init() public {

        try  usr.initializeIlk(ETH_Z) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }
    }

    // Access Invariant - claimfee balance can be issued only by a ward (not a regular user)
    function test_issue_wardonly(uint256 bal) public {
        try usr.try_issue(ETH_A,usr_addr, t0, t2, bal) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }
    }

    // Access Invariant - Claimfee balance cannot be issued after close
    function test_issue_afterclose(uint256 bal) public {
        // set VAT and claimfee to close
        gov_user.close();
        try gov_user.issue(ETH_A, usr_addr, t0 , t3, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "closed" ));
        } catch {
            assert(false); // echidna will fail if any other revert cases are caught
        }
        teardown();
    }

    // Access Invariant - A ward is the only authorized to withdraw claimfee
    function test_withdraw_wardonly(uint256 bal) public {
        try usr.try_withdraw(ETH_A, usr_addr, t0 , t3, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
    }

    // Access Invariant - Ward can withdraw after close
    function test_withdraw_afterclose(uint256 bal) public {
        bytes32 class_t0_t2 = keccak256(abi.encodePacked(ETH_A, t0, t2));

        gov_user.issue(ETH_A, usr_addr, t0, t2, bal); // issue to user
        gov_user.close(); // now, close the contract

        gov_user.withdraw(ETH_A, usr_addr, t0 , t2, bal);

        assert(cfm.cBal(usr_addr, class_t0_t2) == 0);

        teardown();
    }

    // Access Invariant - A ward is the only authorized to insert rates
    function test_insert_wardonly(uint256 newTS) public {
         try usr.try_insert(ETH_A, t0, newTS, test_util.wad(15))  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - A ward is the only authorized to insert rates
    function test_calculate_wardonly(uint256 ratio) public {
         try usr.try_calculate(ETH_A,t3, ratio)  {
         }catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "gate1/not-authorized" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - A ward can set ratio after close
    function test_calculate_afterclose(uint256 ratio) public {

        gov_user.close();

        gov_user.calculate(ETH_A,t3, ratio);
        assert(cfm.ratio(ETH_A, t3) == ratio);
        teardown();
    }

    // Access Invariant - A ward cannot set ratio before close
    function test_calculate_beforeclose() public {
        try gov_user.calculate(ETH_A,t3, test_util.wad(5))  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "not-closed" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - slice
    function test_rewind_afterclose(uint256 bal) public {

        gov_user.issue(ETH_A, usr_addr, t0, t2, bal);
        gov_user.close();

        try  cfm.rewind(ETH_A, usr_addr, t0, t2, t0-1, bal)  {
         } catch Error(string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "closed" ));
        } catch {
            assert(false); // echidna fails on other reverts
        }
        teardown();
    }

    // Access Invariant - delegate to another user
    function test_hope(address delegate) public {
        usr.hope(delegate);
        assert(cfm.can(usr_addr,delegate) == 1);
        teardown();
    }

    // Access Invariant - deny a delegated
    function test_nope(address delegate) public {

        // delegate to
        usr.hope(delegate);

        usr.nope(delegate);
        assert(cfm.can(usr_addr,delegate) == 0);
        teardown();
    }


    function teardown() pure internal {
        revert("undo state changes");
    }


    // Conditional Invariant : Ilk  cannot be initialized until its init in VAT
    function test_cannot_initialize_ilk_vatmiss() public {
        //bytes32 ETH_Z = bytes32("ETH-Z"); // not initialized in vat

        try gov_user.initializeIlk(ETH_Z) {
            assert(cfm.initializedIlks(ETH_Z) == false);
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "ilk/not-initialized"));
        } catch {
            assert(false);  // echidna will fail if any other revert cases are caught
        }

    }

    // Conditional Invariant : Ilk cannot be reinitialized
    function test_already_initialized_ilk() public {
        try gov_user.initializeIlk(ETH_A) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "ilk/initialized"));
        } catch {
            assert(false);  // echidna will fail
        }
    }

    // Conditional Invariant : Cannot move claim balance if not authorized
    function test_move_unauthorized(uint256 bal) public {
        try usr2.moveClaim(usr_addr, usr2_addr, ethA_t0_t2_class, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "not-allowed"));
        } catch {
            assert(false);  // echidna will fail
        }
    }

    // Conditional Invariant : Cannot move claim balance upon insufficient balance
    function test_move_insufficient_balance(uint256 bal) public {

        cfm.issue(ETH_A, usr2_addr, t0, t2, test_util.wad(100)); // issue cf 100 to usr2
        usr2.hope(address(this));

        try usr2.moveClaim(usr2_addr, usr_addr, ethA_t0_t2_class, bal) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "cBal/insufficient-balance"));
        } catch {
            assert(false);  // echidna will fail
        }
    }

    // Conditional Invariant : Snapshot is not allowed only if initialized
    function test_snapshot_not_initialized() public {
       // bytes32 ETH_Z = bytes32("ETH-Z"); // not initialized in vat

        try usr.snapshot(ETH_Z) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "ilk/not-initialized"));
        } catch {
            assert(false); // on any other echidna reverts
        }
    }

    // Conditional Invariant : The insert rate timestamp cannot be in future
    function test_insert_rate_not_in_order(uint256 newRate, uint ts0, uint ts2) public {

        // here t2 greater than the block timestamp (cannot be in future)
        try gov_user.insert(ETH_A, ts0, ts2, newRate) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "rate/timestamps-not-in-order"));
        } catch {
            assert(false); // on any other echidna reverts
        }
    }

    // Conditional Invariant : Overwriting rate timestamp is not allowed on a ILK
    function test_insert_rate_overwrite_notallowed() public {

        vm.warp(t1);
        vat.increaseRate(ETH_A, test_util.wad(10), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.1

        vm.warp(t3);
        vat.increaseRate(ETH_A, test_util.wad(15), address(vow));
        cfm.snapshot(ETH_A); // take a snapshot at t0 @ 1.15

        // here t1 is in between t0 and t2
        try gov_user.insert(ETH_A, t0, t1, ray(115)/100) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "rate/overwrite-disabled"));
        } catch {
            assert(false); // on any other echidna reverts
        }

        teardown();
    }

    // Conditional Invariant : Before rate is not present
    function test_insert_pastrate_not_present() public {

        vm.warp(t3);
        vat.increaseRate(ETH_A, test_util.wad(15), address(vow));
        cfm.snapshot(ETH_A);

        vm.warp(t4);

        // here the rate is not recorded at t1
        try gov_user.insert(ETH_A, t1, t2, ray(115)/100) {
        } catch Error (string memory errmsg) {
            assert(test_util.cmpStr(errmsg, "rate/tBefore-not-present"));
        } catch {
            assert(false); // on any other echidna reverts
        }
        teardown();
    }

    // Conditional Invariant Goal : Claimfee cannot be issued if the rate at issuance ts is not recorded
    function test_cannot_issueClaim_unlessRateRecorded_ThrowsError(uint256 bal) public {

        vm.warp(t3);
        vat.increaseRate(ETH_A, test_util.wad(15), address(vow));

        try gov_user.issue(ETH_A, usr_addr, t2,t3, bal) {
            // no-op
        } catch Error (string memory errorMessage) {
            assert(test_util.cmpStr(errorMessage, "timestamp/invalid") ||
            test_util.cmpStr(errorMessage, "rate/invalid"));
        }  catch {
            assert(false);
        }
    }

    // Conditional : The DAI cannot be collected by unauthroized
    function test_collect_unauthorized(uint256 bal) public {

        try cfm.collect(ETH_A, usr_addr, t0, t2, t1, test_util.wad(bal)) {
        } catch Error (string memory errorMessage) {
            // Echidna - possible errors on call sequence invariants
            assert(test_util.cmpStr(errorMessage, "not-allowed"));
        }  catch {
            assert(false);
        }
    }

    // Conditional : The collect timestamp cannot be after maturity
    function test_collect_post_maturity(uint256 bal) public {

        usr.hope(address(this));
        try cfm.collect(ETH_A, usr_addr, t0, t2, t3, test_util.wad(bal)) {
        } catch Error (string memory errorMessage) {
            assert(test_util.cmpStr(errorMessage, "timestamp/invalid"));
        }  catch {
            assert(false);
        }
        teardown();
    }

    // Conditional : The rate value should be recorded at collect ts
    function test_collect_invalid_collection(uint256 bal) public {

        usr.hope(address(this));
        try cfm.collect(ETH_A, usr_addr, t0, t2, t1, test_util.wad(bal)) {
        } catch Error (string memory errorMessage) {
            assert(test_util.cmpStr(errorMessage, "rate/invalid"));
        }  catch {
            assert(false);
        }
        teardown();
    }


    // Conditional : Unauthorized user cannot invoke rewind
    function test_rewind_unauthorized(uint256 bal) public {
        uint256 t00 = t0 - 5 days; // past  5 days
        try cfm.rewind(ETH_A, usr_addr, t0, t2, t00, bal) {
        } catch Error (string memory errorMsg){
            assert(test_util.cmpStr(errorMsg, "not-allowed"));
        } catch {
            assert(false);
        }
    }

    // Conditional : The rewind ts cannot be between issuance and maturity
    function test_rewind_invalid_rewindts(uint256 bal) public {

        usr.hope(address(this));

        // the rewind ts (t2) cannot be in between issuance and maturity
        try cfm.rewind(ETH_A, usr_addr, t0, t3, t2, bal) {
        } catch Error (string memory errorMsg){
            assert(test_util.cmpStr(errorMsg, "timestamp/invalid"));
        } catch {
            assert(false);
        }
        teardown();
    }

    // Conditional : The rewind fails if rate is not recorded at rewind ts.
    function test_rewind_invalid_rate(uint256 bal) public {

        usr.hope(address(this));

        gov_user.issue(ETH_A, usr_addr, t2,t3, bal);

        // The rate is not recorded at t1
        try cfm.rewind(ETH_A, usr_addr, t2, t3, t1, bal) {
        } catch Error (string memory errorMsg){
            assert(test_util.cmpStr(errorMsg, "rate/invalid"));
        } catch {
            assert(false);
        }
        teardown();
    }

    // Conditional : slice cannot be performed after maturity
     function test_slice_aftermaturity(uint256 bal) public {
        usr.hope(address(this));
        try cfm.slice(ETH_A, usr_addr, t0, t2+1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "timestamp/invalid"));
        } catch {
            assert(false);
        }
        teardown();
     }

     // Conditional : slice cannot be performed after maturity
     function test_slice_unauthorized(uint256 bal) public {
        try cfm.slice(ETH_A, usr_addr, t0, t2+1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "not-allowed"));
        } catch {
            assert(false); // fail on echidna reverts
        }
     }

      // Conditional : slice cannot be invoked before issuance
      function test_slice_beforeissuance(uint256 bal) public {
        usr.hope(address(this));
        try cfm.slice(ETH_A, usr_addr, t0, t0-1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "timestamp/invalid") );
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : Merge cannot be performed after maturity
   /* function test_merge_aftermaturity(uint256 bal) public {

         gov_user.issue(ETH_A, usr_addr, t0, t1, bal);
         gov_user.issue(ETH_A, usr_addr, t1, t2, bal);
         usr.hope(address(this));

        try cfm.merge(ETH_A, usr_addr, t0, t1, t2+1, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "timestamp/invalid"));
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }
     */

     // Conditional : Merge unauthorized
     function test_merge_unauthorized(uint256 bal) public {

         gov_user.issue(ETH_A, usr_addr, t0, t1, bal);
         gov_user.issue(ETH_A, usr_addr, t1, t2, bal);

        try cfm.merge(ETH_A, usr_addr, t0, t1, t2+1, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "not-allowed"));
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
     }

     // Conditional : activate can be invoke only by authorized delegates
     function test_activate_unauthorized(uint256 bal) public {

        try cfm.activate(ETH_A, usr_addr, t0, t1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "not-allowed"));
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
     }

     // Conditional : issuance time stamp should be absent
     function test_activate_invalid_issuancerate(uint256 bal) public {

        usr.hope(address(this));
        try cfm.activate(ETH_A, usr_addr, t0, t1, t2, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "rate/valid"));
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : activation time stamp should be present
     function test_activate_invalid_activationrate(uint256 bal) public {

        usr.hope(address(this));

        gov_user.issue(ETH_A, usr_addr, t1, t3, bal);
        vat.increaseRate(ETH_A, test_util.wad(15), address(vow));
        cfm.snapshot(ETH_A);

        vm.warp(t2);

        try cfm.activate(ETH_A, usr_addr, t1, t2, t3, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "rate/invalid"));
        } catch {
            assert(false); // echidna will fail on any other reverts
        }
        teardown();
     }

     // Conditional : activate invalid timestamp order
     function test_activate_invalid_timestamp(uint256 bal) public {

        usr.hope(address(this));

        try cfm.activate(ETH_A, usr_addr, t2, t3, t1, bal) {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "timestamp/invalid"));
        } catch {
            assert(false);
        }
        teardown();
     }

     function test_close_conditions() public {
        try usr.try_close() {
        } catch Error (string memory errMsg) {
            assert(test_util.cmpStr(errMsg, "close/conditions-not-met"));
        } catch {
            assert(false);
        }
        teardown();
     }

/*
    // Conditional : The rewind fails if rate is same at both issuance and rewind.
    function test_rewind_same_rate(uint256 bal) public {

        usr.hope(address(this));

        vm.warp(t2);
        vat.increaseRate(ETH_A, test_util.wad(5), address(vow)); // same rate
        cfm.snapshot(ETH_A);

        vm.warp(t3);

        gov.issue(ETH_A, usr_addr, t2, t3, bal);

        try cfm.rewind(ETH_A, usr_addr, t2, t3, t0, bal) {
        } catch Error (string memory errorMsg){
            assert(test_util.cmpStr(errorMsg, "rate/np-differnce"));
        } catch {
            assert(false);
        }
        teardown();
    }
*/


    // Fuzz Goal : User transfers claim fee to another user.  The balances are adjusted accordingly.
    function test_moveclaim(CHolder src, CHolder dest, uint256 bal) public  {

        address src_address = address(src);
        address dest_address = address(dest);

        if (src_address == address(0) || dest_address == address(0) || src_address == dest_address) {
           return;
        }
        bytes32 class_iss_mat = keccak256(abi.encodePacked(ETH_A, t0, t2));

        uint256 srcBalance = cfm.cBal(src_address,class_iss_mat);
        uint256 destBalance = cfm.cBal(dest_address, class_iss_mat);

        try src.moveClaim(src_address, dest_address, class_iss_mat, bal) {

            assert(cfm.cBal(src_address, class_iss_mat) == (srcBalance - bal));
            assert(cfm.cBal(dest_address, class_iss_mat) == (destBalance + bal));
        } catch Error (string memory errMessage) {
            assert(
                msg.sender != src_address && test_util.cmpStr(errMessage, "not-allowed") ||
               // cfm.can(msg.sender, src) != 1 && test_util.cmpStr(errMessage, "not-allowed") ||
                cfm.cBal(src_address, class_iss_mat) < bal && test_util.cmpStr(errMessage, "cBal/insufficient-balance")
            );
        }
    }


    // Echidna test : mint DAI in vat for a user
    function test_mint(address userAddress, uint256 amount) internal {
       uint256 preBal = vat.dai(userAddress);
       vat.mint(userAddress, test_util.rad(amount));
       assert(preBal + amount == vat.dai(userAddress));
    }

/*
     function test_issue(address user, uint256 iss, uint256 mat, uint256 bal) public {
         iss = t0;
         mat = t2;


    if (user == address(0)) {
        return;
    }
        bytes32 class_iss_mat = keccak256(abi.encodePacked(ETH_A, iss, mat));
        uint256 pBal = cfm.cBal(user, class_iss_mat);
        uint256 pTotalSupply = cfm.totalSupply(class_iss_mat);

        try cfm.issue(ETH_A, user, iss, mat, bal) {

            assert(cfm.cBal(user, class_iss_mat) == pBal + bal);
            assert(cfm.totalSupply(class_iss_mat) == pTotalSupply - bal);

        } catch Error(string memory error_message) {
            assert(
                cfm.latestRateTimestamp(ETH_A) <= iss  && test_util.cmpStr(error_message, "timestamp/invalid") ||
                block.timestamp > mat && test_util.cmpStr(error_message,"timestamp/invalid") ||
                cfm.rate(ETH_A, iss) == 0 && test_util.cmpStr(error_message, "rate/invalid")
            );
        } catch {
            assert(false); // if echidna fails on any other reverts
        }
    }
    */

    function test_issue(address user, uint256 iss, uint256 mat, uint256 bal) public {

        bytes32 class_iss_mat = keccak256(abi.encodePacked(ETH_A, iss, mat));
        uint256 pBal = cfm.cBal(user, class_iss_mat);
        uint256 pTotalSupply = cfm.totalSupply(class_iss_mat);

        try cfm.issue(ETH_A, user, iss, mat, bal) {

            assert(cfm.cBal(user, class_iss_mat) == pBal + bal);
            assert(cfm.totalSupply(class_iss_mat) == pTotalSupply - bal);

        } catch Error(string memory error_message) {
            assert(
                cfm.latestRateTimestamp(ETH_A) <= iss  && test_util.cmpStr(error_message, "timestamp/invalid") ||
                block.timestamp > mat && test_util.cmpStr(error_message,"timestamp/invalid") ||
                cfm.rate(ETH_A, iss) == 0 && test_util.cmpStr(error_message, "rate/invalid")
            );
        } catch {
            assert(false); // if echidna fails on any other reverts
        }
    }

    function test_initialize(bytes32 ilk) public {

        // Initialize the ilk in VAT
        vat.ilkSetup(ilk);
        vat.increaseRate(ilk, test_util.wad(5), address(vow));

        try cfm.initializeIlk(ilk) {
            assert(cfm.initializedIlks(ilk) == true);
            assert(cfm.latestRateTimestamp(ilk) == block.timestamp);

        } catch Error(string memory error_message) {
            assert(
                cfm.initializedIlks(ilk) == false && test_util.cmpStr(error_message, "ilk/initialized") ||
                cfm.wards(msg.sender) == 0 && test_util.cmpStr(error_message, "gate1/not-authorized")
             );
        } catch {
            assert(false);
        }
    }

    function test_snapshot(bytes32 ilk) public {

        vat.ilkSetup(ilk);
        vat.increaseRate(ilk, test_util.wad(10), address(vow));
        try cfm.snapshot(ilk) {

            assert(cfm.rate(ilk,block.timestamp) == test_util.wad(10));
            assert(cfm.latestRateTimestamp(ilk) == block.timestamp);

        } catch Error(string memory error_message) {
            assert(
                cfm.initializedIlks(ilk) == false && test_util.cmpStr(error_message, "ilk/not-initialized")
            );
        } catch {
            assert(false);
        }

    }

    function test_insert(bytes32 ilk, uint256 tBefore, uint256 tInsert, uint256 rate) public {
         vat.ilkSetup(ilk);
         vat.increaseRate(ilk, test_util.wad(10), address(vow));
         cfm.initializeIlk(ilk);

        // cfm.rely(sender, usr); // this can be removed
         try cfm.insert(ilk, tBefore, tInsert, rate) {

                assert(cfm.rate(ilk, tInsert) == rate);

         } catch Error(string memory error_message) {
             assert(
                 (tBefore >= tInsert)  && test_util.cmpStr(error_message, "rate/timestamps-not-in-order") ||
                 (tInsert >= cfm.latestRateTimestamp(ilk)) && test_util.cmpStr(error_message, "rate/timestamps-not-in-order") ||
                 rate < RAY && test_util.cmpStr(error_message, "rate/below-one") ||
                 cfm.rate(ilk, tInsert) != 0 && test_util.cmpStr(error_message, "rate/overwrite-disabled") ||
                 cfm.rate(ilk, tBefore) == 0 && test_util.cmpStr(error_message, "rate/tBefore-not-present") ||
                 cfm.rate(ilk, tBefore) > rate && test_util.cmpStr(error_message, "rate/invalid") ||
                 cfm.rate(ilk, cfm.latestRateTimestamp(ilk)) < rate &&   test_util.cmpStr(error_message, "rate/invalid")
             );
         }catch {
             assert(false);
         }
     }

    function test_collect(bytes32 ilk, address usr_address, uint256 issTS, uint256 matTS, uint256 collectTS, uint256 bal) public {

         vat.ilkSetup(ilk);
         vat.increaseRate(ilk, test_util.wad(10), address(vow));
         cfm.initializeIlk(ilk);
         // issue ??

        uint256 issRate = cfm.rate(ilk, issTS);
        uint256 collectRate = cfm.rate(ilk, collectTS);

        bytes32 ilkClassIssMat = keccak256(abi.encodePacked(ilk, issTS, matTS)); // iss, mat
        bytes32 ilkClassColMat = keccak256(abi.encodePacked(ilk, collectTS, matTS)); // collect, mat
        uint256 issBalance = cfm.cBal(usr_address, ilkClassIssMat);
        uint256 collectBalance = cfm.cBal(usr_address, ilkClassColMat);

        try cfm.collect(ilk, usr_address, issTS, matTS, collectTS, bal) {

            assert(cfm.cBal(usr_address, ilkClassIssMat) == issBalance - bal);
            if (collectTS != matTS) {
                assert(cfm.cBal(usr_address, ilkClassColMat) == collectBalance + bal);
            }

        } catch Error(string memory error_message) {
            assert(
                msg.sender != usr_address && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && test_util.cmpStr(error_message, "not-allowed") ||
                issRate == 0 && test_util.cmpStr(error_message, "rate/invalid") ||
                collectRate == 0 && test_util.cmpStr(error_message, "rate/invalid") ||
                issTS > collectTS && test_util.cmpStr(error_message, "timestamp/invalid") ||
                collectTS > matTS && test_util.cmpStr(error_message, "timestamp/invalid")
            );
        } catch {
            assert(false);
        }
    }

    function  test_slice(bytes32 ilk, address usr_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t3 = keccak256(abi.encodePacked(ilk, ts1, ts3)); // t1, t3
        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t3 =  cfm.cBal(usr_address, ilkClass_t1_t3);
        uint256  prevBalance_t1_t2 =  cfm.cBal(usr_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(usr_address, ilkClass_t2_t3);


        try cfm.slice(ilk, usr_address, t1, t2, t3, bal) {

            assert(cfm.cBal(usr_address, ilkClass_t1_t3) == prevBalance_t1_t3 - bal);
            assert(cfm.cBal(usr_address, ilkClass_t1_t2) == prevBalance_t1_t2 + bal);
            assert(cfm.cBal(usr_address, ilkClass_t2_t3) == prevBalance_t2_t3 + bal);

        } catch Error (string memory error_message) {
            assert(
                msg.sender != usr_address && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && test_util.cmpStr(error_message, "not-allowed") ||
                t1 >= t2 && test_util.cmpStr(error_message, "timestamp/invalid") ||
                t2 >= t3 && test_util.cmpStr(error_message, "timestamp/invalid") ||
                cfm.cBal(usr_address, ilkClass_t1_t3) < bal && test_util.cmpStr(error_message, "cBal/insufficient-balance")
            );
        } catch {
            assert(false);
        }
    }

    function test_merge(bytes32 ilk, address usr_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t3 = keccak256(abi.encodePacked(ilk, ts1, ts3)); // t1, t3
        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t3 =  cfm.cBal(usr_address, ilkClass_t1_t3);
        uint256  prevBalance_t1_t2 =  cfm.cBal(usr_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(usr_address, ilkClass_t2_t3);

        try cfm.merge(ilk, usr_address, ts1, ts2, ts3, bal) {

            assert(cfm.cBal(usr_address, ilkClass_t1_t3) == prevBalance_t1_t3 + bal);
            assert(cfm.cBal(usr_address, ilkClass_t1_t2) == prevBalance_t1_t2 - bal);
            assert(cfm.cBal(usr_address, ilkClass_t2_t3) == prevBalance_t2_t3 - bal);

        } catch Error (string memory error_message) {
            assert(
                msg.sender != usr_address && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && test_util.cmpStr(error_message, "not-allowed") ||
                !(ts1 < ts2 && ts2 < ts3) && test_util.cmpStr(error_message, "timestamp/invalid") ||
                cfm.cBal(usr_address, ilkClass_t1_t2) < bal && test_util.cmpStr(error_message, "cBal/insufficient-balance") ||
                cfm.cBal(usr_address, ilkClass_t2_t3) < bal && test_util.cmpStr(error_message, "cBal/insufficient-balance")
            );
        }
    }

    function test_rewind(bytes32 ilk, address usr_address, uint256 issuanceTs, uint256 maturityTs, uint256 rewindTs, uint256 bal) public {

        uint256 issuanceRate = cfm.rate(ilk, issuanceTs);
        bytes32 ilkClass_iss_mat = keccak256(abi.encodePacked(ilk, issuanceTs, maturityTs)); // iss, mat
        bytes32 ilkClass_rew_mat = keccak256(abi.encodePacked(ilk, rewindTs, maturityTs)); // rewind, mat

        uint256  prevBalance_iss_mat =  cfm.cBal(usr_address, ilkClass_iss_mat);
        uint256  prevBalance_rew_mat =  cfm.cBal(usr_address, ilkClass_rew_mat);
        uint256 user_dai_bal = vat.dai(usr_address);

        try cfm.rewind(ilk, usr_address, issuanceTs, maturityTs, rewindTs, bal) {

            assert(cfm.cBal(usr_address, ilkClass_iss_mat) == prevBalance_iss_mat - bal);
            assert(cfm.cBal(usr_address, ilkClass_rew_mat) == prevBalance_rew_mat + bal);
            assert(vat.dai(usr_address) == user_dai_bal); // user dai bal remains same

        } catch Error(string memory error_message) {
            assert(
                msg.sender != usr_address && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, usr_address) != 1 && test_util.cmpStr(error_message, "not-allowed") ||
                rewindTs > issuanceTs && test_util.cmpStr(error_message, "timestamp/invalid") ||
                issuanceTs > maturityTs && test_util.cmpStr(error_message, "timestamp/invalid") ||
                cfm.rate(ilk, rewindTs) == 0 && test_util.cmpStr(error_message, "rate/invalid") ||
                issuanceRate == 0 && test_util.cmpStr(error_message, "rate/invalid") ||
                issuanceRate <= cfm.rate(ilk, rewindTs) && test_util.cmpStr(error_message, "rate/no-difference")
            );
        } catch {
            assert(false);
        }
    }

    function test_activate(bytes32 ilk, address user_address, uint256 ts1, uint256 ts2, uint256 ts3, uint256 bal) public {

        bytes32 ilkClass_t1_t2 = keccak256(abi.encodePacked(ilk, ts1, ts2)); // t1, t2
        bytes32 ilkClass_t2_t3 = keccak256(abi.encodePacked(ilk, ts2, ts3)); // t2, t3

        uint256  prevBalance_t1_t2 =  cfm.cBal(user_address, ilkClass_t1_t2);
        uint256  prevBalance_t2_t3 =  cfm.cBal(user_address, ilkClass_t2_t3);

        try cfm.activate(ilk, user_address, ts1, ts2, ts3, bal) {
            assert(cfm.cBal(user_address, ilkClass_t1_t2) == prevBalance_t1_t2 - bal);
            assert(cfm.cBal(user_address, ilkClass_t2_t3) == prevBalance_t2_t3 + bal);

        } catch Error (string memory error_message) {
            assert(
                ts1 >= ts2 && test_util.cmpStr(error_message, "timestamp/invalid") ||
                ts2 >= ts3 && test_util.cmpStr(error_message, "timestamp/invalid") ||
                msg.sender != user_address && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.can(msg.sender, user_address) != 1 && test_util.cmpStr(error_message, "not-allowed") ||
                cfm.rate(ilk, ts1) !=0 && test_util.cmpStr(error_message, "rate/invalid") ||
                cfm.rate(ilk, ts2) == 0 && test_util.cmpStr(error_message, "rate/invalid")
            );
        } catch {
            assert(false);
        }
    }

    function test_withdraw(bytes32 ilk, address user_address, uint256 issuanceTs, uint256 maturityTs, uint256 bal) public {

        bytes32 ilkClass_iss_mat = keccak256(abi.encodePacked(ilk, issuanceTs, maturityTs)); // iss, mat
        uint256 prevBalance = cfm.cBal(user_address, ilkClass_iss_mat);

        try cfm.withdraw(ilk, user_address, issuanceTs, maturityTs, bal) {
            assert(cfm.cBal(user_address, ilkClass_iss_mat) == prevBalance - bal);
        }catch Error (string memory error_message) {
            assert(
                cfm.wards(msg.sender) == 0 && test_util.cmpStr(error_message, "gate/not-authorized") ||
                cfm.cBal(user_address, ilkClass_iss_mat) < bal && test_util.cmpStr(error_message, "cBal/insufficient-balance")
            );
        } catch {
            assert(false);
        }
    }

    function test_rely(address usr_address) public {
        try cfm.rely(usr_address) {
            assert(cfm.wards(usr_address) == 1);
        } catch Error(string memory error_message) {
            assert(false);
        }
    }

    function ray(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAY);
    }

}