// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@zkevm/interfaces/IPolygonZkEVMBridge.sol";

import {CommonAdminOwner} from "./CommonAdminOwner.sol";

import {IUSDC} from "./interfaces/IUSDC.sol";
import {LibPermit} from "./helpers/LibPermit.sol";

/// @title NativeConverter
/// @notice This contract will receive BridgeWrappedUSDC on zkEVM and issue USDC.e on the zkEVM.
/// @notice This contract will hold the minter role giving it the ability to mint USDC-e based on
/// inflows of BridgeWrappedUSDC. This contract will also have a permissionless publicly
/// callable function called “migrate” which when called will burn all BridgedWrappedUSDC
/// on the L2, and send a message to the bridge that causes all of the corresponding
/// backing L1 USD to be sent to the L1Escrow. This aligns the balance of the L1Escrow
/// contract with the total supply of USDC-e on the zkEVM.
contract NativeConverter is CommonAdminOwner {
    using SafeERC20Upgradeable for IUSDC;

    event Convert(address indexed from, address indexed to, uint256 amount);
    event Deconvert(address indexed from, address indexed to, uint256 amount);
    event Migrate(uint256 amount);

    /// @notice the PolygonZkEVMBridge deployed on the zkEVM
    IPolygonZkEVMBridge public bridge;

    /// @notice The ID used internally by the bridge to identify L1 messages. Initially
    /// set to be `0`
    uint32 public l1NetworkId;

    /// @notice The address of the L1Escrow
    address public l1Escrow;

    /// @notice The L2 USDC-e deployed on the zkEVM
    IUSDC public zkUSDCe;

    /// @notice The default L2 USDC TokenWrapped token deployed on the zkEVM
    IUSDC public zkBWUSDC;

    constructor() {
        // override default OZ behaviour that sets msg.sender as the owner
        // set the owner of the implementation to an address that can not change anything
        _transferOwnership(address(1));
    }

    /// @notice Setup the state variables of the upgradeable NativeConverter contract
    /// @notice The owner is the address that is able to pause and unpause function calls
    /// @param owner_ the address that will be able to pause and unpause the contract,
    /// as well as transfer the ownership of the contract
    /// @param bridge_ the address of the PolygonZkEVMBridge deployed on the zkEVM
    /// @param l1NetworkId_ the ID used internally by the bridge to identify L1 messages
    /// @param l1EscrowProxy_ the address of the L1Escrow deployed on the L1
    /// @param zkUSDCe_ the address of the L2 USDC-e deployed on the zkEVM
    /// @param zkBWUSDC_ the address of the default L2 USDC TokenWrapped token deployed on the zkEVM
    function initialize(
        address owner_,
        address admin_,
        address bridge_,
        uint32 l1NetworkId_,
        address l1EscrowProxy_,
        address zkUSDCe_,
        address zkBWUSDC_
    ) external onlyProxy onlyAdmin initializer {
        require(bridge_ != address(0), "INVALID_BRIDGE");
        require(l1EscrowProxy_ != address(0), "INVALID_L1ESCROW");
        require(zkUSDCe_ != address(0), "INVALID_USDC_E");
        require(zkBWUSDC_ != address(0), "INVALID_BW_UDSC");
        require(owner_ != address(0), "INVALID_OWNER");
        require(admin_ != address(0), "INVALID_ADMIN");

        __CommonAdminOwner_init();

        _transferOwnership(owner_);
        _changeAdmin(admin_);

        bridge = IPolygonZkEVMBridge(bridge_);
        l1NetworkId = l1NetworkId_;
        l1Escrow = l1EscrowProxy_;
        zkUSDCe = IUSDC(zkUSDCe_);
        zkBWUSDC = IUSDC(zkBWUSDC_);
    }

    /// @notice Converts L2 BridgeWrappedUSDC to L2 USDC-e
    /// @dev The NativeConverter transfers L2 BridgeWrappedUSDC from the caller to itself and
    /// mints L2 USDC-e to the caller
    /// @param receiver address that will receive L2 USDC-e on the L2
    /// @param amount amount of L2 BridgeWrappedUSDC to convert
    /// @param permitData data for the permit call on the L2 BridgeWrappedUSDC
    function convert(
        address receiver,
        uint256 amount,
        bytes calldata permitData
    ) external whenNotPaused {
        require(receiver != address(0), "INVALID_RECEIVER");
        require(amount > 0, "INVALID_AMOUNT");

        if (permitData.length > 0)
            LibPermit.permit(address(zkBWUSDC), amount, permitData);

        // transfer the wrapped usdc to the converter, and mint back native usdc
        zkBWUSDC.safeTransferFrom(msg.sender, address(this), amount);
        zkUSDCe.mint(receiver, amount);

        emit Convert(msg.sender, receiver, amount);
    }

    function deconvert(
        address receiver,
        uint256 amount,
        bytes calldata permitData
    ) external whenNotPaused {
        require(receiver != address(0), "INVALID_RECEIVER");
        require(amount > 0, "INVALID_AMOUNT");
        require(amount <= zkBWUSDC.balanceOf(address(this)), "AMOUNT_TOO_LARGE");

        if (permitData.length > 0)
            LibPermit.permit(address(zkUSDCe), amount, permitData);

        // transfer native usdc from user to the converter, and burn it
        zkUSDCe.safeTransferFrom(msg.sender, address(this), amount);
        zkUSDCe.burn(amount);

        // and then send bridge wrapped usdc to the user
        zkBWUSDC.safeTransfer(receiver, amount);

        emit Deconvert(msg.sender, receiver, amount);
    }

    /// @notice Migrates L2 BridgeWrappedUSDC USDC to L1 USDC
    /// @dev Any BridgeWrappedUSDC transfered in by previous calls to
    /// `convert` will be burned and the corresponding
    /// L1 USDC will be sent to the L1Escrow via a message to the bridge
    function migrate() external onlyOwner whenNotPaused {
        // Anyone can call migrate() on NativeConverter to
        // have all zkBridgeWrappedUSDC withdrawn via the PolygonZkEVMBridge
        // moving the L1_USDC held in the PolygonZkEVMBridge to L1Escrow

        uint256 amount = zkBWUSDC.balanceOf(address(this));

        if (amount > 0) {
            zkBWUSDC.approve(address(bridge), amount);

            bridge.bridgeAsset(
                l1NetworkId,
                l1Escrow,
                amount,
                address(zkBWUSDC),
                true, // forceUpdateGlobalExitRoot
                "" // empty permitData because we're doing approve
            );

            emit Migrate(amount);
        }
    }
}
