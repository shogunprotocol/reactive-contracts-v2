// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/interfaces/IVaultFactory.sol";
import "../src/mocks/MockERC20.sol";
import "../src/Vault.sol";

// Mock VaultFactory for testing
contract MockVaultFactory {
    address public defaultManager;
    address public defaultAgent;
    address public treasury;
    uint256 public creationFee;
    uint256 public defaultWithdrawalFee;
    uint256 public defaultYieldRate;
    uint256 public vaultCounter;

    mapping(uint256 => address) public vaults;
    mapping(address => uint256[]) public userVaults;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vault,
        address indexed creator
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    error InvalidManager();
    error InvalidAgent();
    error InvalidTreasury();
    error InsufficientCreationFee();

    constructor(
        address _defaultManager,
        address _defaultAgent,
        address _treasury,
        uint256 _creationFee,
        uint256 _defaultWithdrawalFee,
        uint256 _defaultYieldRate
    ) {
        if (_defaultManager == address(0)) revert InvalidManager();
        if (_defaultAgent == address(0)) revert InvalidAgent();
        if (_treasury == address(0)) revert InvalidTreasury();

        defaultManager = _defaultManager;
        defaultAgent = _defaultAgent;
        treasury = _treasury;
        creationFee = _creationFee;
        defaultWithdrawalFee = _defaultWithdrawalFee;
        defaultYieldRate = _defaultYieldRate;
    }

    function createVault(
        address asset,
        string memory name,
        string memory symbol,
        address manager,
        address agent,
        uint256 withdrawalFee,
        uint256 yieldRate
    ) external payable returns (address vault) {
        if (msg.value < creationFee) revert InsufficientCreationFee();

        // Use defaults if zero address provided
        address vaultManager = manager != address(0) ? manager : defaultManager;
        address vaultAgent = agent != address(0) ? agent : defaultAgent;
        uint256 vaultWithdrawalFee = withdrawalFee > 0
            ? withdrawalFee
            : defaultWithdrawalFee;
        uint256 vaultYieldRate = yieldRate > 0 ? yieldRate : defaultYieldRate;

        vault = address(
            new Vault(
                IERC20(asset),
                name,
                symbol,
                vaultManager,
                vaultAgent,
                vaultWithdrawalFee,
                vaultYieldRate,
                treasury
            )
        );

        vaultCounter++;
        vaults[vaultCounter] = vault;
        userVaults[msg.sender].push(vaultCounter);

        emit VaultCreated(vaultCounter, vault, msg.sender);

        // Send creation fee to treasury
        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
        }
    }

    function setCreationFee(uint256 newFee) external {
        uint256 oldFee = creationFee;
        creationFee = newFee;
        emit CreationFeeUpdated(oldFee, newFee);
    }

    function getUserVaults(
        address user
    ) external view returns (uint256[] memory) {
        return userVaults[user];
    }
}

contract VaultFactoryTest is Test {
    MockVaultFactory public vaultFactory;
    MockERC20 public mockToken;

    address public owner;
    address public defaultManager;
    address public defaultAgent;
    address public treasury;
    address public user1;
    address public user2;
    address public customManager;
    address public customAgent;

    uint256 constant CREATION_FEE = 0.01 ether;
    uint256 constant DEFAULT_WITHDRAWAL_FEE = 100; // 1% default withdrawal fee
    uint256 constant DEFAULT_YIELD_RATE = 500; // 5% default yield rate

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vault,
        address indexed creator
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        owner = address(this);
        defaultManager = makeAddr("defaultManager");
        defaultAgent = makeAddr("defaultAgent");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        customManager = makeAddr("customManager");
        customAgent = makeAddr("customAgent");

        // Deploy mock token
        mockToken = new MockERC20("Test Token", "TEST", 18);

        // Deploy VaultFactory
        vaultFactory = new MockVaultFactory(
            defaultManager,
            defaultAgent,
            treasury,
            CREATION_FEE,
            DEFAULT_WITHDRAWAL_FEE,
            DEFAULT_YIELD_RATE
        );

        // Fund users for creation fees
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetInitialValuesCorrectly() public {
        assertEq(vaultFactory.defaultManager(), defaultManager);
        assertEq(vaultFactory.defaultAgent(), defaultAgent);
        assertEq(vaultFactory.treasury(), treasury);
        assertEq(vaultFactory.creationFee(), CREATION_FEE);
        assertEq(vaultFactory.defaultWithdrawalFee(), DEFAULT_WITHDRAWAL_FEE);
        assertEq(vaultFactory.vaultCounter(), 0);
    }

    function test_Constructor_RevertWithInvalidParameters() public {
        // Invalid manager
        vm.expectRevert(MockVaultFactory.InvalidManager.selector);
        new MockVaultFactory(
            address(0),
            defaultAgent,
            treasury,
            CREATION_FEE,
            DEFAULT_WITHDRAWAL_FEE,
            DEFAULT_YIELD_RATE
        );

        // Invalid agent
        vm.expectRevert(MockVaultFactory.InvalidAgent.selector);
        new MockVaultFactory(
            defaultManager,
            address(0),
            treasury,
            CREATION_FEE,
            DEFAULT_WITHDRAWAL_FEE,
            DEFAULT_YIELD_RATE
        );

        // Invalid treasury
        vm.expectRevert(MockVaultFactory.InvalidTreasury.selector);
        new MockVaultFactory(
            defaultManager,
            defaultAgent,
            address(0),
            CREATION_FEE,
            DEFAULT_WITHDRAWAL_FEE,
            DEFAULT_YIELD_RATE
        );
    }

    // ============ Vault Creation Tests ============

    function test_CreateVault_WithDefaultParameters() public {
        vm.prank(user1);
        vm.expectEmit(true, false, true, true);
        emit VaultCreated(1, address(0), user1); // address(0) as placeholder

        address vault = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Test Vault",
            "tVault",
            address(0), // Use default manager
            address(0), // Use default agent
            0, // Use default withdrawal fee
            0 // Use default yield rate
        );

        assertTrue(vault != address(0), "Vault should be created");
        assertEq(
            vaultFactory.vaultCounter(),
            1,
            "Vault counter should increment"
        );
        assertEq(vaultFactory.vaults(1), vault, "Vault should be stored");

        uint256[] memory userVaults = vaultFactory.getUserVaults(user1);
        assertEq(userVaults.length, 1, "User should have one vault");
        assertEq(userVaults[0], 1, "User vault ID should be 1");
    }

    function test_CreateVault_WithCustomParameters() public {
        vm.prank(user1);
        address vault = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Custom Vault",
            "cVault",
            customManager,
            customAgent,
            200, // 2% withdrawal fee
            1000 // 10% yield rate
        );

        assertTrue(vault != address(0), "Custom vault should be created");

        // Verify vault has custom parameters
        Vault vaultContract = Vault(vault);
        assertEq(vaultContract.name(), "Custom Vault");
        assertEq(vaultContract.symbol(), "cVault");
    }

    function test_CreateVault_RevertWithInsufficientFee() public {
        vm.prank(user1);
        vm.expectRevert(MockVaultFactory.InsufficientCreationFee.selector);
        vaultFactory.createVault{value: CREATION_FEE - 1}(
            address(mockToken),
            "Test Vault",
            "tVault",
            address(0),
            address(0),
            0,
            0
        );
    }

    function test_CreateVault_AcceptExcessFee() public {
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 excessFee = CREATION_FEE + 0.005 ether;

        vm.prank(user1);
        address vault = vaultFactory.createVault{value: excessFee}(
            address(mockToken),
            "Test Vault",
            "tVault",
            address(0),
            address(0),
            0,
            0
        );

        assertTrue(
            vault != address(0),
            "Vault should be created with excess fee"
        );
        assertEq(
            treasury.balance,
            treasuryBalanceBefore + excessFee,
            "Treasury should receive full fee"
        );
    }

    function test_CreateVault_MultipleVaults() public {
        // User1 creates first vault
        vm.prank(user1);
        address vault1 = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 1",
            "V1",
            address(0),
            address(0),
            0,
            0
        );

        // User2 creates second vault
        vm.prank(user2);
        address vault2 = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 2",
            "V2",
            address(0),
            address(0),
            0,
            0
        );

        assertEq(vaultFactory.vaultCounter(), 2, "Should have 2 vaults");
        assertEq(
            vaultFactory.vaults(1),
            vault1,
            "First vault should be stored"
        );
        assertEq(
            vaultFactory.vaults(2),
            vault2,
            "Second vault should be stored"
        );

        uint256[] memory user1Vaults = vaultFactory.getUserVaults(user1);
        uint256[] memory user2Vaults = vaultFactory.getUserVaults(user2);

        assertEq(user1Vaults.length, 1, "User1 should have 1 vault");
        assertEq(user2Vaults.length, 1, "User2 should have 1 vault");
        assertEq(user1Vaults[0], 1, "User1 vault should be ID 1");
        assertEq(user2Vaults[0], 2, "User2 vault should be ID 2");
    }

    function test_CreateVault_SameUserMultipleVaults() public {
        // User1 creates multiple vaults
        vm.startPrank(user1);

        address vault1 = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 1",
            "V1",
            address(0),
            address(0),
            0,
            0
        );

        address vault2 = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 2",
            "V2",
            address(0),
            address(0),
            0,
            0
        );

        vm.stopPrank();

        uint256[] memory userVaults = vaultFactory.getUserVaults(user1);
        assertEq(userVaults.length, 2, "User should have 2 vaults");
        assertEq(userVaults[0], 1, "First vault should be ID 1");
        assertEq(userVaults[1], 2, "Second vault should be ID 2");
    }

    // ============ Admin Functions Tests ============

    function test_SetCreationFee_UpdatesFeeCorrectly() public {
        uint256 newFee = 0.02 ether;

        vm.expectEmit(true, true, false, false);
        emit CreationFeeUpdated(CREATION_FEE, newFee);

        vaultFactory.setCreationFee(newFee);

        assertEq(
            vaultFactory.creationFee(),
            newFee,
            "Creation fee should be updated"
        );
    }

    function test_SetCreationFee_AllowsZeroFee() public {
        vaultFactory.setCreationFee(0);
        assertEq(
            vaultFactory.creationFee(),
            0,
            "Should allow zero creation fee"
        );

        // Should be able to create vault with zero fee
        vm.prank(user1);
        address vault = vaultFactory.createVault{value: 0}(
            address(mockToken),
            "Free Vault",
            "fVault",
            address(0),
            address(0),
            0,
            0
        );

        assertTrue(vault != address(0), "Should create vault with zero fee");
    }

    // ============ View Functions Tests ============

    function test_GetUserVaults_ReturnsCorrectVaults() public {
        // Initially empty
        uint256[] memory initialVaults = vaultFactory.getUserVaults(user1);
        assertEq(initialVaults.length, 0, "Should start with no vaults");

        // Create some vaults
        vm.startPrank(user1);
        vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 1",
            "V1",
            address(0),
            address(0),
            0,
            0
        );

        vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Vault 2",
            "V2",
            address(0),
            address(0),
            0,
            0
        );
        vm.stopPrank();

        uint256[] memory userVaults = vaultFactory.getUserVaults(user1);
        assertEq(userVaults.length, 2, "Should return 2 vaults");
        assertEq(userVaults[0], 1, "First vault should be ID 1");
        assertEq(userVaults[1], 2, "Second vault should be ID 2");
    }

    // ============ Integration Tests ============

    function test_CreatedVault_IsFullyFunctional() public {
        vm.prank(user1);
        address vaultAddress = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Functional Vault",
            "fVault",
            address(0),
            address(0),
            0,
            0
        );

        Vault vault = Vault(vaultAddress);

        // Test basic vault functionality
        assertEq(
            vault.asset(),
            address(mockToken),
            "Vault should have correct asset"
        );
        assertEq(
            vault.name(),
            "Functional Vault",
            "Vault should have correct name"
        );
        assertEq(vault.symbol(), "fVault", "Vault should have correct symbol");

        // Test deposit functionality
        uint256 depositAmount = 1000e18;
        mockToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        mockToken.approve(vaultAddress, depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(
            vault.balanceOf(user1),
            depositAmount,
            "User should receive shares"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "Vault should have correct total assets"
        );
    }

    // ============ Fuzz Tests ============

    function testFuzz_CreateVault_WithVariousFees(uint256 fee) public {
        fee = bound(fee, CREATION_FEE, 1 ether);

        vm.deal(user1, fee);

        vm.prank(user1);
        address vault = vaultFactory.createVault{value: fee}(
            address(mockToken),
            "Fuzz Vault",
            "fVault",
            address(0),
            address(0),
            0,
            0
        );

        assertTrue(
            vault != address(0),
            "Should create vault with any sufficient fee"
        );
        assertEq(treasury.balance, fee, "Treasury should receive the fee");
    }

    function testFuzz_CreateVault_WithVariousParameters(
        uint256 withdrawalFee,
        uint256 yieldRate
    ) public {
        withdrawalFee = bound(withdrawalFee, 0, 1000); // 0-10%
        yieldRate = bound(yieldRate, 0, 2000); // 0-20%

        vm.prank(user1);
        address vault = vaultFactory.createVault{value: CREATION_FEE}(
            address(mockToken),
            "Fuzz Vault",
            "fVault",
            customManager,
            customAgent,
            withdrawalFee,
            yieldRate
        );

        assertTrue(
            vault != address(0),
            "Should create vault with various parameters"
        );
    }
}
