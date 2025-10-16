// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Core Contracts
import {TaskManager} from "../src/core/TaskManager.sol";
import {SubmissionManager} from "../src/core/SubmissionManager.sol";
import {ReputationManager} from "../src/core/ReputationManager.sol";
import {AllowlistManager} from "../src/core/AllowlistManager.sol";
import {Treasury} from "../src/core/Treasury.sol";
import {ArbitrationManager} from "../src/core/ArbitrationManager.sol";
import {HermisSBT} from "../src/core/HermisSBT.sol";

// Guards
import {GlobalGuard} from "../src/guards/global/GlobalGuard.sol";
import {SubmissionGuard} from "../src/guards/task/SubmissionGuard.sol";
import {ReviewGuard} from "../src/guards/task/ReviewGuard.sol";

// Strategies
import {SimpleAdoptionStrategy} from "../src/strategies/adoption/SimpleAdoptionStrategy.sol";
import {BasicRewardStrategy} from "../src/strategies/reward/BasicRewardStrategy.sol";

// Libraries
import {DataTypes} from "../src/libraries/DataTypes.sol";

/**
 * @title DeployHermis
 * @notice Comprehensive deployment script for the entire Hermis Protocol
 * @dev Deploys all contracts, initializes configurations, and sets up integrations
 */
contract DeployHermis is Script {
    // Deployment addresses (will be set at runtime)
    address internal admin;
    address internal platformFeeRecipient;

    // Core contracts
    Treasury public treasury;
    HermisSBT public hermisSBT;
    ReputationManager public reputationManager;
    AllowlistManager public allowlistManager;
    TaskManager public taskManager;
    SubmissionManager public submissionManager;
    ArbitrationManager public arbitrationManager;

    // Guards
    GlobalGuard public globalGuard;
    SubmissionGuard public submissionGuard;
    ReviewGuard public reviewGuard;

    // Strategies
    SimpleAdoptionStrategy public simpleAdoptionStrategy;
    BasicRewardStrategy public basicRewardStrategy;

    // Mock token for testing (optional)
    address public stakeToken;

    // Configuration constants
    uint256 constant ARBITRATION_FEE = 0.1 ether;
    string constant SBT_NAME = "Hermis Soul Bound Token";
    string constant SBT_SYMBOL = "HSBT";
    string constant SBT_BASE_URI = "https://hermis.protocol/metadata/";
    string constant SBT_CONTRACT_URI = "https://hermis.protocol/contract-metadata";

    function run() external {
        // Detect environment based on chain ID
        bool isLocalNetwork = block.chainid == 31337 || block.chainid == 1337;

        // Get deployer private key based on environment
        uint256 deployerPrivateKey;
        if (isLocalNetwork) {
            // Local network: use LOCAL_PRIVATE_KEY from .env (Anvil account #0)
            deployerPrivateKey = vm.envOr(
                "LOCAL_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
            );
            console.log("Environment: Local Network (Anvil)");
        } else {
            // Production network: use PRIVATE_KEY from .env
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            console.log("Environment: Production Network");
        }

        console.log("====================================");
        console.log("Hermis Protocol Deployment Starting");
        console.log("====================================");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Get admin address from msg.sender (set by broadcast)
        admin = msg.sender;
        platformFeeRecipient = admin;

        console.log("Deployer:", admin);
        console.log("Platform Fee Recipient:", platformFeeRecipient);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Deploy in correct order
        deployInfrastructure();
        deployStrategies();
        deployCoreContracts();
        deployGuards(); // Guards need ReputationManager, so deploy after core

        // Configure all contracts (works for both local and production)
        configureContracts();
        initializeGuards();
        initializeStrategies();
        setupAllowlist();

        vm.stopBroadcast();

        // Log deployment summary
        logDeploymentSummary();

        // Save deployment addresses to file
        saveDeploymentAddresses();
    }

    /**
     * @notice Deploy infrastructure layer contracts
     */
    function deployInfrastructure() internal {
        console.log("1. Deploying Infrastructure Layer...");

        // Deploy Treasury
        treasury = new Treasury(admin);
        console.log("   Treasury deployed at:", address(treasury));

        // Deploy HermisSBT
        hermisSBT = new HermisSBT(admin, SBT_NAME, SBT_SYMBOL, SBT_BASE_URI, SBT_CONTRACT_URI);
        console.log("   HermisSBT deployed at:", address(hermisSBT));

        console.log("");
    }

    /**
     * @notice Deploy guard contracts
     * @dev Guards are deployed after ReputationManager since they need it in constructor
     */
    function deployGuards() internal {
        console.log("4. Deploying Access Control Layer (Guards)...");

        // Deploy Guards with admin as owner
        globalGuard = new GlobalGuard(admin, address(reputationManager));
        console.log("   GlobalGuard deployed at:", address(globalGuard));

        submissionGuard = new SubmissionGuard(admin, address(reputationManager));
        console.log("   SubmissionGuard deployed at:", address(submissionGuard));

        reviewGuard = new ReviewGuard(admin, address(reputationManager));
        console.log("   ReviewGuard deployed at:", address(reviewGuard));

        console.log("");
    }

    /**
     * @notice Deploy strategy contracts
     */
    function deployStrategies() internal {
        console.log("2. Deploying Strategy Execution Layer...");

        // Deploy SimpleAdoptionStrategy with admin as owner
        simpleAdoptionStrategy = new SimpleAdoptionStrategy(admin);
        console.log("   SimpleAdoptionStrategy deployed at:", address(simpleAdoptionStrategy));

        // Deploy BasicRewardStrategy with admin as owner
        basicRewardStrategy = new BasicRewardStrategy(admin);
        console.log("   BasicRewardStrategy deployed at:", address(basicRewardStrategy));

        console.log("");
    }

    /**
     * @notice Deploy core business contracts
     */
    function deployCoreContracts() internal {
        console.log("3. Deploying Core Business Layer...");

        // Deploy AllowlistManager (needed for TaskManager)
        AllowlistManager allowlistManagerImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, admin);
        ERC1967Proxy allowlistManagerProxy = new ERC1967Proxy(address(allowlistManagerImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistManagerProxy));
        console.log("   AllowlistManager deployed at:", address(allowlistManager));

        // Deploy ReputationManager (uses address(0) as placeholder for stake token)
        stakeToken = address(0); // Use ETH for staking in this deployment
        reputationManager = new ReputationManager(admin, address(treasury), stakeToken);
        console.log("   ReputationManager deployed at:", address(reputationManager));

        // Deploy TaskManager
        TaskManager taskManagerImpl = new TaskManager();
        bytes memory taskManagerInitData = abi.encodeWithSelector(
            TaskManager.initialize.selector,
            admin,
            address(treasury),
            address(reputationManager),
            address(allowlistManager)
        );
        ERC1967Proxy taskManagerProxy = new ERC1967Proxy(address(taskManagerImpl), taskManagerInitData);
        taskManager = TaskManager(address(taskManagerProxy));
        console.log("   TaskManager deployed at:", address(taskManager));

        // Deploy SubmissionManager
        SubmissionManager submissionManagerImpl = new SubmissionManager();
        bytes memory submissionManagerInitData = abi.encodeWithSelector(
            SubmissionManager.initialize.selector,
            admin,
            address(taskManager),
            address(reputationManager),
            address(treasury),
            address(basicRewardStrategy)
        );
        ERC1967Proxy submissionManagerProxy =
            new ERC1967Proxy(address(submissionManagerImpl), submissionManagerInitData);
        submissionManager = SubmissionManager(address(submissionManagerProxy));
        console.log("   SubmissionManager deployed at:", address(submissionManager));

        // Deploy ArbitrationManager
        ArbitrationManager arbitrationManagerImpl = new ArbitrationManager();
        bytes memory arbitrationManagerInitData = abi.encodeWithSelector(
            ArbitrationManager.initialize.selector,
            admin,
            address(reputationManager),
            address(submissionManager),
            address(treasury),
            ARBITRATION_FEE
        );
        ERC1967Proxy arbitrationManagerProxy =
            new ERC1967Proxy(address(arbitrationManagerImpl), arbitrationManagerInitData);
        arbitrationManager = ArbitrationManager(address(arbitrationManagerProxy));
        console.log("   ArbitrationManager deployed at:", address(arbitrationManager));

        console.log("");
    }

    /**
     * @notice Configure contract relationships and permissions
     * @dev Executed within vm.startBroadcast(), so msg.sender is the deployer
     */
    function configureContracts() internal {
        console.log("5. Configuring Contract Relationships...");

        // Connect HermisSBT and ReputationManager
        hermisSBT.setReputationManager(address(reputationManager));
        reputationManager.setHermisSBT(address(hermisSBT));

        // Set Treasury authorizations
        treasury.setAuthorizedContract(address(reputationManager), true);
        treasury.setAuthorizedContract(address(taskManager), true);
        treasury.setAuthorizedContract(address(submissionManager), true);
        treasury.setAuthorizedContract(address(arbitrationManager), true);

        // Set TaskManager authorizations
        taskManager.setAuthorizedContract(address(submissionManager), true);
        taskManager.setAuthorizedContract(address(reputationManager), true);

        // Set ReputationManager authorizations
        reputationManager.setAuthorizedContract(address(taskManager), true);
        reputationManager.setAuthorizedContract(address(submissionManager), true);
        reputationManager.setAuthorizedContract(address(arbitrationManager), true);

        // Set SubmissionManager authorizations
        submissionManager.setAuthorizedContract(address(taskManager), true);

        console.log("   Contract relationships configured");
        console.log("");
    }

    /**
     * @notice Setup AllowlistManager with default approved contracts
     * @dev Executed within vm.startBroadcast()
     */
    function setupAllowlist() internal {
        console.log("8. Setting up AllowlistManager...");

        // Allow all deployed guards
        allowlistManager.allowGuard(address(globalGuard));
        allowlistManager.allowGuard(address(submissionGuard));
        allowlistManager.allowGuard(address(reviewGuard));

        // Allow all deployed strategies
        allowlistManager.allowStrategy(address(simpleAdoptionStrategy));
        allowlistManager.allowStrategy(address(basicRewardStrategy));

        // Allow ETH (address(0)) and stake token
        allowlistManager.allowToken(address(0)); // ETH

        if (stakeToken != address(0)) {
            allowlistManager.allowToken(stakeToken);
        }

        console.log("   AllowlistManager configured");
        console.log("");
    }

    /**
     * @notice Initialize Guards with default configurations
     * @dev Executed within vm.startBroadcast()
     */
    function initializeGuards() internal {
        console.log("6. Initializing Guards...");

        // Initialize GlobalGuard
        bytes memory globalGuardConfig = abi.encode(
            GlobalGuard.GlobalGuardConfig({
                minReputationForNormal: 600,
                atRiskThreshold: 200,
                baseStakeAmount: 1 ether,
                enforceStakeForAtRisk: true,
                allowBlacklistedUsers: false
            })
        );
        globalGuard.initializeGuard(globalGuardConfig);

        // Initialize SubmissionGuard
        bytes memory submissionGuardConfig = abi.encode(
            SubmissionGuard.SubmissionConfig({
                minReputationScore: 500,
                requireCategoryExpertise: false,
                requiredCategory: "",
                minCategoryScore: 700,
                maxFailedSubmissions: 3,
                enforceSuccessRate: false,
                minSuccessRate: 80
            })
        );
        submissionGuard.initializeGuard(submissionGuardConfig);

        // Initialize ReviewGuard
        bytes memory reviewGuardConfig = abi.encode(
            ReviewGuard.ReviewConfig({
                minReputationScore: 600,
                requireCategoryExpertise: false,
                requiredCategory: "",
                minCategoryScore: 750,
                minReviewCount: 5,
                enforceAccuracyRate: false,
                minAccuracyRate: 85
            })
        );
        reviewGuard.initializeGuard(reviewGuardConfig);

        console.log("   Guards initialized");
        console.log("");
    }

    /**
     * @notice Initialize Strategies with default configurations
     * @dev Executed within vm.startBroadcast()
     */
    function initializeStrategies() internal {
        console.log("7. Initializing Strategies...");

        // Initialize SimpleAdoptionStrategy
        bytes memory adoptionConfig = abi.encode(
            SimpleAdoptionStrategy.SimpleAdoptionConfig({
                minReviewsRequired: 3,
                approvalThreshold: 60,
                rejectionThreshold: 40,
                expirationTime: 7 days,
                allowTimeBasedAdoption: false,
                autoAdoptionTime: 0
            })
        );
        simpleAdoptionStrategy.initializeStrategy(adoptionConfig);

        // Initialize BasicRewardStrategy
        bytes memory rewardConfig = abi.encode(
            BasicRewardStrategy.BasicRewardConfig({
                creatorPercentage: 70,
                reviewerPercentage: 20,
                platformPercentage: 10,
                accuracyBonus: 20,
                accuracyPenalty: 10,
                minReviewerReward: 0,
                maxReviewerReward: 0
            })
        );
        basicRewardStrategy.initializeRewardStrategy(rewardConfig);

        console.log("   Strategies initialized");
        console.log("");
    }

    /**
     * @notice Log complete deployment summary
     */
    function logDeploymentSummary() internal view {
        console.log("====================================");
        console.log("Deployment Summary");
        console.log("====================================");
        console.log("");
        console.log("Infrastructure Layer:");
        console.log("  Treasury:", address(treasury));
        console.log("  HermisSBT:", address(hermisSBT));
        console.log("");
        console.log("Core Business Layer:");
        console.log("  AllowlistManager:", address(allowlistManager));
        console.log("  ReputationManager:", address(reputationManager));
        console.log("  TaskManager:", address(taskManager));
        console.log("  SubmissionManager:", address(submissionManager));
        console.log("  ArbitrationManager:", address(arbitrationManager));
        console.log("");
        console.log("Access Control Layer:");
        console.log("  GlobalGuard:", address(globalGuard));
        console.log("  SubmissionGuard:", address(submissionGuard));
        console.log("  ReviewGuard:", address(reviewGuard));
        console.log("");
        console.log("Strategy Execution Layer:");
        console.log("  SimpleAdoptionStrategy:", address(simpleAdoptionStrategy));
        console.log("  BasicRewardStrategy:", address(basicRewardStrategy));
        console.log("");
        console.log("Configuration:");
        console.log("  Admin:", admin);
        console.log("  Platform Fee Recipient:", platformFeeRecipient);
        console.log("  Stake Token:", stakeToken == address(0) ? "ETH" : vm.toString(stakeToken));
        console.log("  Arbitration Fee:", ARBITRATION_FEE);
        console.log("");
        console.log("====================================");
        console.log("Deployment Completed Successfully!");
        console.log("====================================");
    }

    /**
     * @notice Save deployment addresses to a file for later verification
     */
    function saveDeploymentAddresses() internal {
        string memory json = "deployment";

        vm.serializeAddress(json, "TREASURY", address(treasury));
        vm.serializeAddress(json, "HERMIS_SBT", address(hermisSBT));
        vm.serializeAddress(json, "ALLOWLIST_MANAGER", address(allowlistManager));
        vm.serializeAddress(json, "REPUTATION_MANAGER", address(reputationManager));
        vm.serializeAddress(json, "TASK_MANAGER", address(taskManager));
        vm.serializeAddress(json, "SUBMISSION_MANAGER", address(submissionManager));
        vm.serializeAddress(json, "ARBITRATION_MANAGER", address(arbitrationManager));
        vm.serializeAddress(json, "GLOBAL_GUARD", address(globalGuard));
        vm.serializeAddress(json, "SUBMISSION_GUARD", address(submissionGuard));
        vm.serializeAddress(json, "REVIEW_GUARD", address(reviewGuard));
        vm.serializeAddress(json, "SIMPLE_ADOPTION_STRATEGY", address(simpleAdoptionStrategy));
        string memory finalJson = vm.serializeAddress(json, "BASIC_REWARD_STRATEGY", address(basicRewardStrategy));

        // Write to deployments directory
        string memory filename = string.concat("./deployments/deployment-", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, filename);

        console.log("");
        console.log("Deployment addresses saved to:", filename);
    }
}
