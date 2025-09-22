// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/INonfungiblePositionManager.sol";

contract MockNonfungiblePositionManager is
    INonfungiblePositionManager,
    Ownable
{
    using SafeERC20 for IERC20;

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    // Storage
    mapping(uint256 => Position) public positionData;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 public nextTokenId = 1;

    // Mock state for realistic behavior
    uint256 public constant FEE_MULTIPLIER = 100; // 1% fee for testing
    uint256 public totalFeesCollected0;
    uint256 public totalFeesCollected1;

    // Events
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event Approval(
        address indexed owner,
        address indexed approved,
        uint256 indexed tokenId
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    constructor() Ownable(msg.sender) {}

    function mint(
        MintParams calldata params
    )
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(block.timestamp <= params.deadline, "deadline-exceeded");
        require(params.tickLower < params.tickUpper, "invalid-range");

        // Calculate amounts (simplified - assume full amounts are used)
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        // Check minimums
        require(amount0 >= params.amount0Min, "amount0-min");
        require(amount1 >= params.amount1Min, "amount1-min");

        // Calculate liquidity (simplified formula)
        liquidity = uint128((amount0 + amount1) / 1000); // Simplified
        require(liquidity > 0, "zero-liquidity");

        // Create position
        tokenId = nextTokenId++;
        positionData[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: uint128(amount0), // Store tokens as owed
            tokensOwed1: uint128(amount1) // Store tokens as owed
        });

        ownerOf[tokenId] = params.recipient;

        // Transfer tokens from sender
        if (amount0 > 0) {
            IERC20(params.token0).safeTransferFrom(
                msg.sender,
                address(this),
                amount0
            );
        }
        if (amount1 > 0) {
            IERC20(params.token1).safeTransferFrom(
                msg.sender,
                address(this),
                amount1
            );
        }

        // Emit NFT transfer event
        emit Transfer(address(0), params.recipient, tokenId);
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        require(block.timestamp <= params.deadline, "deadline-exceeded");
        require(ownerOf[params.tokenId] != address(0), "position-not-exists");

        Position storage position = positionData[params.tokenId];
        require(position.liquidity > 0, "position-empty");

        // Calculate amounts (simplified)
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        // Check minimums
        require(amount0 >= params.amount0Min, "amount0-min");
        require(amount1 >= params.amount1Min, "amount1-min");

        // Calculate additional liquidity
        liquidity = uint128((amount0 + amount1) / 1000);
        require(liquidity > 0, "zero-additional-liquidity");

        position.liquidity += liquidity;
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);

        // Transfer tokens
        if (amount0 > 0) {
            IERC20(position.token0).safeTransferFrom(
                msg.sender,
                address(this),
                amount0
            );
        }
        if (amount1 > 0) {
            IERC20(position.token1).safeTransferFrom(
                msg.sender,
                address(this),
                amount1
            );
        }
    }

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external returns (uint256 amount0, uint256 amount1) {
        require(block.timestamp <= params.deadline, "deadline-exceeded");
        require(ownerOf[params.tokenId] != address(0), "position-not-exists");

        Position storage position = positionData[params.tokenId];
        require(
            position.liquidity >= params.liquidity,
            "insufficient-liquidity"
        );

        // Calculate amounts to return (proportional to owed tokens in position)
        uint256 totalLiquidity = position.liquidity;
        amount0 =
            (uint256(position.tokensOwed0) * params.liquidity) /
            totalLiquidity;
        amount1 =
            (uint256(position.tokensOwed1) * params.liquidity) /
            totalLiquidity;

        // Check minimums
        require(amount0 >= params.amount0Min, "amount0-min");
        require(amount1 >= params.amount1Min, "amount1-min");

        // Update position
        position.liquidity -= params.liquidity;

        // Add to tokens owed (will be collected later)
        position.tokensOwed0 = uint128(uint256(position.tokensOwed0) - amount0);
        position.tokensOwed1 = uint128(uint256(position.tokensOwed1) - amount1);

        // Actually return the amounts to the caller (this matches Algebra behavior)
        if (amount0 > 0) {
            IERC20(position.token0).safeTransfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20(position.token1).safeTransfer(msg.sender, amount1);
        }
    }

    function collect(
        CollectParams calldata params
    ) external returns (uint256 amount0, uint256 amount1) {
        require(ownerOf[params.tokenId] != address(0), "position-not-exists");

        Position storage position = positionData[params.tokenId];

        // Calculate amounts to collect
        amount0 = uint256(position.tokensOwed0) < params.amount0Max
            ? uint256(position.tokensOwed0)
            : params.amount0Max;
        amount1 = uint256(position.tokensOwed1) < params.amount1Max
            ? uint256(position.tokensOwed1)
            : params.amount1Max;

        // Reset owed amounts
        position.tokensOwed0 -= uint128(amount0);
        position.tokensOwed1 -= uint128(amount1);

        // Transfer tokens
        if (amount0 > 0) {
            IERC20(position.token0).safeTransfer(params.recipient, amount0);
        }
        if (amount1 > 0) {
            IERC20(position.token1).safeTransfer(params.recipient, amount1);
        }
    }

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position storage position = positionData[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        require(owner == msg.sender, "not-owner");
        getApproved[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    // Additional ERC721-like functions for testing
    function _transferFrom(address from, address to, uint256 tokenId) internal {
        require(ownerOf[tokenId] == from, "not-owner");
        require(
            msg.sender == from ||
                getApproved[tokenId] == msg.sender ||
                isApprovedForAll[from][msg.sender],
            "not-approved"
        );

        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        _transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external {
        _transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata
    ) external {
        _transferFrom(from, to, tokenId);
    }

    // Simulate fee collection over time
    function addFees(uint256 tokenId, uint256 fee0, uint256 fee1) external {
        Position storage position = positionData[tokenId];
        position.tokensOwed0 += uint128(fee0);
        position.tokensOwed1 += uint128(fee1);
    }

    // Emergency function to set position data for testing
    function setPositionData(
        uint256 tokenId,
        uint128 liquidity,
        uint128 owed0,
        uint128 owed1
    ) external {
        Position storage position = positionData[tokenId];
        position.liquidity = liquidity;
        position.tokensOwed0 = owed0;
        position.tokensOwed1 = owed1;
    }

    /// @notice Debug function to check position data
    function debugPosition(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0_,
            address token1_,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 owed0,
            uint128 owed1
        )
    {
        Position storage position = positionData[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @notice Check NFPM token balance
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
