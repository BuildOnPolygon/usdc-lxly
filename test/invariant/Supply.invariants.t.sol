// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "lib/forge-std/src/console.sol";
import "lib/forge-std/src/Test.sol";

import {HandlerState, LxLyHandler, Operation} from "./LxLyHandler.sol";
import {Base} from "../Base.sol";

contract Supply is Base {
    HandlerState private _state;
    LxLyHandler private _handler;

    function setUp() public override {
        // initialize base
        super.setUp();
        super._fundActorsAndBridge();

        // create and init the handler
        _state = new HandlerState(vm, _l1Fork);
        address stateAddr = address(_state);

        _handler = new LxLyHandler(
            _l1Fork,
            _l2Fork,
            _l1NetworkId,
            _l2NetworkId,
            _actors,
            _bridge,
            _erc20L1Usdc,
            _erc20L2Usdc,
            _erc20L2Wusdc
        );
        _handler.init(_state, _l1Escrow, _nativeConverter, _minterBurner);
        address handlerAddr = address(_handler);

        vm.makePersistent(stateAddr);
        vm.makePersistent(handlerAddr);

        // register the actors
        targetSender(_actors[0]);
        targetSender(_actors[1]);
        targetSender(_actors[2]);
        targetSender(_actors[3]);
        targetSender(_actors[4]);
        targetSender(_actors[5]);
        targetSender(_actors[6]);

        // register the selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _handler.deposit.selector;
        selectors[1] = _handler.withdraw.selector;
        selectors[2] = _handler.convert.selector;
        selectors[3] = _handler.migrate.selector;
        targetSelector(FuzzSelector({addr: handlerAddr, selectors: selectors}));

        // register the contract
        targetContract(handlerAddr);

        excludeContract(_bridge);
        excludeContract(stateAddr);
    }

    // the test

    function invariantGigaTest() public {
        console.log("-------- invariantGigaTest");

        Operation op = _state.getCurrentOp();
        _state.setNoOp();

        if (op == Operation.DEPOSITING) _assertDepositConditionals();
        else if (op == Operation.WITHDRAWING) _assertWithdrawConditionals();
        else if (op == Operation.CONVERTING) _assertConvertConditionals();
        else if (op == Operation.MIGRATING) _assertMigrateConditionals();

        // TODO: assertUpgradeConditionals();
    }

    // helpers

    function _assertDepositConditionals() private {
        (
            bool continueExecution,
            address receiver,
            uint256 amount,
            uint256 l1BalanceBefore,
            uint256 l2BalanceBefore,
            ,
            ,

        ) = _state.getState();

        if (continueExecution) {
            // check currentActor's L1_USDC balance decreased
            vm.selectFork(_l1Fork);
            assertEq(
                l1BalanceBefore -
                    _erc20L1Usdc.balanceOf(_handler.currentActor()),
                amount
            );

            // manually trigger the "bridging"
            _claimBridgeMessage(_l1Fork, _l2Fork);

            // check zkReceiver's L2_USDC balance increased
            vm.selectFork(_l2Fork);
            assertEq(
                _erc20L2Usdc.balanceOf(receiver) - l2BalanceBefore,
                amount
            );

            // check main invariant
            _assertUsdcSupplyAndBalancesMatch();
        }
    }

    function _assertWithdrawConditionals() private {
        (
            bool continueExecution,
            address receiver,
            uint256 amount,
            uint256 l1BalanceBefore,
            uint256 l2BalanceBefore,
            ,
            ,

        ) = _state.getState();

        if (continueExecution) {
            // check currentActor's L2_USDC balance decreased
            vm.selectFork(_l2Fork);
            assertEq(
                l2BalanceBefore -
                    _erc20L2Usdc.balanceOf(_handler.currentActor()),
                amount
            );

            // manually trigger the "bridging"
            _claimBridgeMessage(_l2Fork, _l1Fork);

            // check l1Receiver's L1_USDC balance increased
            vm.selectFork(_l1Fork);
            assertEq(
                _erc20L1Usdc.balanceOf(receiver) - l1BalanceBefore,
                amount
            );

            // check main invariant
            _assertUsdcSupplyAndBalancesMatch();
        }
    }

    function _assertConvertConditionals() private {
        (
            bool continueExecution,
            address receiver,
            uint256 amount,
            ,
            ,
            uint256 senderWUSDCBal,
            uint256 receiverUSDCBal,
            uint256 converterWUSDCBal
        ) = _state.getState();

        if (continueExecution) {
            vm.selectFork(_l2Fork);

            // check currentActor's L2_BWUSDC balance decreased
            assertEq(
                senderWUSDCBal -
                    _erc20L2Wusdc.balanceOf(_handler.currentActor()),
                amount
            );

            // check receiver's L2_USDC balance increased
            assertEq(
                _erc20L2Usdc.balanceOf(receiver) - receiverUSDCBal,
                amount
            );

            // check _nativeConverter's L2_BWUSDC balance increased
            assertEq(
                _erc20L2Wusdc.balanceOf(address(_nativeConverter)) -
                    converterWUSDCBal,
                amount
            );

            // check main invariant
            _assertUsdcSupplyAndBalancesMatch();
        }
    }

    function _assertMigrateConditionals() private {
        (
            bool continueExecution,
            ,
            uint256 amount,
            uint256 l1BalanceBefore,
            ,
            ,
            ,

        ) = _state.getState();

        if (continueExecution) {
            // check _nativeConverter L2_BWUSDC balance decreased
            vm.selectFork(_l2Fork);
            assertEq(_erc20L2Wusdc.balanceOf(address(_nativeConverter)), 0);

            // manually trigger the "bridging"
            _claimBridgeAsset(_l2NetworkId, _l1NetworkId);

            // check _l1Escrow L1_USDC balance increased
            vm.selectFork(_l1Fork);
            assertEq(
                _erc20L1Usdc.balanceOf(address(_l1Escrow)) - l1BalanceBefore,
                amount
            );

            // check main invariant
            _assertUsdcSupplyAndBalancesMatch();
        }
    }
}
