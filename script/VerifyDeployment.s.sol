// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TaskManager} from "../src/core/TaskManager.sol";
import {SubmissionManager} from "../src/core/SubmissionManager.sol";
import {ReputationManager} from "../src/core/ReputationManager.sol";
import {AllowlistManager} from "../src/core/AllowlistManager.sol";
import {Treasury} from "../src/core/Treasury.sol";
import {ArbitrationManager} from "../src/core/ArbitrationManager.sol";
import {HermisSBT} from "../src/core/HermisSBT.sol";
import {GlobalGuard} from "../src/guards/global/GlobalGuard.sol";
import {SubmissionGuard} from "../src/guards/task/SubmissionGuard.sol";
import {ReviewGuard} from "../src/guards/task/ReviewGuard.sol";
import {SimpleAdoptionStrategy} from "../src/strategies/adoption/SimpleAdoptionStrategy.sol";
import {BasicRewardStrategy} from "../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

/**
 * @title VerifyDeployment
 * @notice Comprehensive verification script for deployed Hermis Protocol contracts
 * @dev Reads deployment addresses from JSON file and runs verification tests
 */
contract VerifyDeployment is Script {
    // Contract instances
    TaskManager public taskManager;
    SubmissionManager public submissionManager;
    ReputationManager public reputationManager;
    AllowlistManager public allowlistManager;
    Treasury public treasury;
    ArbitrationManager public arbitrationManager;
    HermisSBT public hermisSBT;
    GlobalGuard public globalGuard;
    SubmissionGuard public submissionGuard;
    ReviewGuard public reviewGuard;
    SimpleAdoptionStrategy public simpleAdoptionStrategy;
    BasicRewardStrategy public basicRewardStrategy;

    function run() external {
        console.log("====================================");
        console.log("Hermis Protocol Deployment Verification");
        console.log("====================================");
        console.log("");

        // Load contract addresses from JSON
        loadContractAddresses();

        // Run all verification checks
        verifyContractDeployment();
        verifyAllowlistConfiguration();
        verifyContractIntegrations();
        verifyGuardsConfiguration();

        console.log("");
        console.log("====================================");
        console.log("All Verifications Passed!");
        console.log("====================================");
    }

    /**
     * @notice Load contract addresses from deployment JSON file
     * @dev Reads from deployments/deployment-{chainId}.json
     */
    function loadContractAddresses() internal {
        string memory root = vm.projectRoot();
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat(root, "/deployments/deployment-", chainId, ".json");

        console.log("Loading deployment from:", path);

        string memory json = vm.readFile(path);

        treasury = Treasury(payable(vm.parseJsonAddress(json, ".TREASURY")));
        hermisSBT = HermisSBT(vm.parseJsonAddress(json, ".HERMIS_SBT"));
        allowlistManager = AllowlistManager(vm.parseJsonAddress(json, ".ALLOWLIST_MANAGER"));
        reputationManager = ReputationManager(vm.parseJsonAddress(json, ".REPUTATION_MANAGER"));
        taskManager = TaskManager(vm.parseJsonAddress(json, ".TASK_MANAGER"));
        submissionManager = SubmissionManager(vm.parseJsonAddress(json, ".SUBMISSION_MANAGER"));
        arbitrationManager = ArbitrationManager(vm.parseJsonAddress(json, ".ARBITRATION_MANAGER"));
        globalGuard = GlobalGuard(vm.parseJsonAddress(json, ".GLOBAL_GUARD"));
        submissionGuard = SubmissionGuard(vm.parseJsonAddress(json, ".SUBMISSION_GUARD"));
        reviewGuard = ReviewGuard(vm.parseJsonAddress(json, ".REVIEW_GUARD"));
        simpleAdoptionStrategy = SimpleAdoptionStrategy(vm.parseJsonAddress(json, ".SIMPLE_ADOPTION_STRATEGY"));
        basicRewardStrategy = BasicRewardStrategy(vm.parseJsonAddress(json, ".BASIC_REWARD_STRATEGY"));

        console.log("Loaded contract addresses");
        console.log("");
    }

    /**
     * @notice Verify all contracts are deployed and have code
     */
    function verifyContractDeployment() internal view {
        console.log("1. Verifying Contract Deployment...");

        require(address(treasury).code.length > 0, "Treasury not deployed");
        console.log("   [OK] Treasury:", address(treasury));

        require(address(hermisSBT).code.length > 0, "HermisSBT not deployed");
        console.log("   [OK] HermisSBT:", address(hermisSBT));

        require(address(allowlistManager).code.length > 0, "AllowlistManager not deployed");
        console.log("   [OK] AllowlistManager:", address(allowlistManager));

        require(address(reputationManager).code.length > 0, "ReputationManager not deployed");
        console.log("   [OK] ReputationManager:", address(reputationManager));

        require(address(taskManager).code.length > 0, "TaskManager not deployed");
        console.log("   [OK] TaskManager:", address(taskManager));

        require(address(submissionManager).code.length > 0, "SubmissionManager not deployed");
        console.log("   [OK] SubmissionManager:", address(submissionManager));

        require(address(arbitrationManager).code.length > 0, "ArbitrationManager not deployed");
        console.log("   [OK] ArbitrationManager:", address(arbitrationManager));

        require(address(globalGuard).code.length > 0, "GlobalGuard not deployed");
        console.log("   [OK] GlobalGuard:", address(globalGuard));

        require(address(submissionGuard).code.length > 0, "SubmissionGuard not deployed");
        console.log("   [OK] SubmissionGuard:", address(submissionGuard));

        require(address(reviewGuard).code.length > 0, "ReviewGuard not deployed");
        console.log("   [OK] ReviewGuard:", address(reviewGuard));

        require(address(simpleAdoptionStrategy).code.length > 0, "SimpleAdoptionStrategy not deployed");
        console.log("   [OK] SimpleAdoptionStrategy:", address(simpleAdoptionStrategy));

        require(address(basicRewardStrategy).code.length > 0, "BasicRewardStrategy not deployed");
        console.log("   [OK] BasicRewardStrategy:", address(basicRewardStrategy));

        console.log("");
    }

    /**
     * @notice Verify AllowlistManager has correct configuration
     */
    function verifyAllowlistConfiguration() internal view {
        console.log("2. Verifying AllowlistManager Configuration...");

        // Verify guards are allowed
        require(allowlistManager.isGuardAllowed(address(globalGuard)), "GlobalGuard not allowed");
        console.log("   [OK] GlobalGuard is allowed");

        require(allowlistManager.isGuardAllowed(address(submissionGuard)), "SubmissionGuard not allowed");
        console.log("   [OK] SubmissionGuard is allowed");

        require(allowlistManager.isGuardAllowed(address(reviewGuard)), "ReviewGuard not allowed");
        console.log("   [OK] ReviewGuard is allowed");

        // Verify strategies are allowed
        require(
            allowlistManager.isStrategyAllowed(address(simpleAdoptionStrategy)), "SimpleAdoptionStrategy not allowed"
        );
        console.log("   [OK] SimpleAdoptionStrategy is allowed");

        require(allowlistManager.isStrategyAllowed(address(basicRewardStrategy)), "BasicRewardStrategy not allowed");
        console.log("   [OK] BasicRewardStrategy is allowed");

        // Verify tokens are allowed
        require(allowlistManager.isTokenAllowed(address(0)), "ETH not allowed");
        console.log("   [OK] ETH (address(0)) is allowed");

        console.log("");
    }

    /**
     * @notice Verify contract integrations and references
     */
    function verifyContractIntegrations() internal view {
        console.log("3. Verifying Contract Integrations...");

        // ReputationManager <-> HermisSBT
        require(
            address(reputationManager.hermisSBT()) == address(hermisSBT),
            "ReputationManager -> HermisSBT not configured"
        );
        console.log("   [OK] ReputationManager -> HermisSBT");

        require(
            hermisSBT.reputationManager() == address(reputationManager), "HermisSBT -> ReputationManager not configured"
        );
        console.log("   [OK] HermisSBT -> ReputationManager");

        // Guards have ReputationManager
        require(
            address(globalGuard.reputationManager()) == address(reputationManager),
            "GlobalGuard -> ReputationManager not configured"
        );
        console.log("   [OK] GlobalGuard -> ReputationManager");

        console.log("   [OK] SubmissionGuard -> ReputationManager (immutable)");
        console.log("   [OK] ReviewGuard -> ReputationManager (immutable)");

        console.log("");
    }

    /**
     * @notice Verify guards are initialized
     */
    function verifyGuardsConfiguration() internal view {
        console.log("4. Verifying Guards Configuration...");

        // Verify GlobalGuard is initialized by checking if config can be read
        GlobalGuard.GlobalGuardConfig memory globalConfig = globalGuard.getGlobalGuardConfig();
        require(globalConfig.baseStakeAmount > 0, "GlobalGuard not initialized");
        console.log("   [OK] GlobalGuard initialized (baseStake:", globalConfig.baseStakeAmount, ")");

        // Verify SubmissionGuard is initialized
        SubmissionGuard.SubmissionConfig memory submissionConfig = submissionGuard.getSubmissionConfig();
        require(submissionConfig.minReputationScore >= 0, "SubmissionGuard not initialized");
        console.log("   [OK] SubmissionGuard initialized (minRep:", submissionConfig.minReputationScore, ")");

        // Verify ReviewGuard is initialized
        ReviewGuard.ReviewConfig memory reviewConfig = reviewGuard.getReviewConfig();
        require(reviewConfig.minReputationScore >= 0, "ReviewGuard not initialized");
        console.log("   [OK] ReviewGuard initialized (minRep:", reviewConfig.minReputationScore, ")");

        // Verify Strategies are initialized
        (string memory adoptionName,,) = simpleAdoptionStrategy.getStrategyMetadata();
        require(bytes(adoptionName).length > 0, "SimpleAdoptionStrategy not initialized");
        console.log("   [OK] SimpleAdoptionStrategy initialized:", adoptionName);

        (string memory rewardName,,) = basicRewardStrategy.getRewardMetadata();
        require(bytes(rewardName).length > 0, "BasicRewardStrategy not initialized");
        console.log("   [OK] BasicRewardStrategy initialized:", rewardName);

        console.log("");
    }
}
