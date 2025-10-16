# Hermis Protocol Technical Architecture Documentation

---

## Table of Contents

1. [Business Architecture Design](#1-business-architecture-design)
2. [Smart Contract Architecture](#2-smart-contract-architecture)
3. [Core Functional Modules](#3-core-functional-modules)
4. [Development Logic and Design Patterns](#4-development-logic-and-design-patterns)
5. [System Integration Standards](#5-system-integration-standards)
6. [Economic Model Design](#6-economic-model-design)
7. [Security Mechanisms](#7-security-mechanisms)
8. [Smart Contract Testing System](#8-smart-contract-testing-system)
9. [Contract Deployment and Operations](#9-contract-deployment-and-operations)
10. [Technical Innovation Highlights](#10-technical-innovation-highlights)

---

## 1. Business Architecture Design

### 1.1 Business Process Architecture

```
Task Publisher ────→ Task Creation ────→ Task Publishing ────→ Collaborator Bidding ────→ Work Submission
    ↑                                                                                        ↓
    │                                                                                 Peer Review Validation
    │                                                                                        ↓
Reward Distribution ←──── Task Completion ←──── Community Consensus ←──── Review Aggregation ←──── Multiple Reviews
```

### 1.2 Participant Ecosystem

**🏢 Task Publishers**
- Enterprises, project teams, individual employers
- Publish specific requirements and tasks
- Provide task rewards and detailed descriptions
- Have task management and cancellation privileges

**👨‍💻 Collaborators (Workers)**
- Freelancers, development teams, creators
- Take on tasks based on skills and interests
- Submit work and solutions
- Improve reputation through quality work

**👩‍⚖️ Reviewers**
- Community members with professional skills
- Evaluate quality of submitted work
- Provide professional feedback and improvement suggestions
- Receive review rewards and reputation enhancement

**⚖️ Arbitrators**
- Platform management team or elected members
- Handle disputes and appeals
- Make final rulings and remedial measures
- Maintain platform fairness and order

### 1.3 Business Model Innovation

**Reputation-Driven Access Mechanism**: Establish a tiered access system through reputation scores and staking requirements to ensure participant quality

**Community-Governed Quality Control**: Adopt peer review mechanism allowing professional community members to assess work quality, reducing subjective bias

**Dynamic Incentive Participation Motivation**: Adjust reputation and incentives based on performance, encouraging continuous quality output

**Transparent Dispute Resolution**: All dispute handling processes and results are recorded on-chain to ensure fairness

---

## 2. Smart Contract Architecture

### 2.1 Core Contract Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Smart Contract System Architecture            │
├─────────────────────────────────────────────────────────────────┤
│  Core Business Layer                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │TaskManager  │  │SubmissionMgr│  │ReputationMgr│               │
│  │Task Mgmt    │  │Submission   │  │Reputation   │               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  Security Management Layer                                       │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │              AllowlistManager (Allowlist Manager)         │   │
│  │  Unified management of platform-verified Guards,          │   │
│  │  Strategies, and Tokens                                   │   │
│  └───────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Access Control Layer                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │GlobalGuard  │  │SubmissionGuard│ │ReviewGuard  │               │
│  │Global Guard │  │Submission   │  │Review Guard │               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  Strategy Execution Layer                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │AdoptionStrategy│ │RewardStrategy│ │GovernanceStr│               │
│  │Adoption     │  │Reward       │  │Governance   │               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
├─────────────────────────────────────────────────────────────────┤
│  Infrastructure Layer                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │   Treasury  │  │  HermisSBT  │  │ArbitrationMgr│               │
│  │   Treasury  │  │  Identity   │  │  Arbitration│               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      Blockchain Foundation Layer                 │
│              Ethereum Mainnet / Layer 2 / Sidechain              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Core Business Contracts

**TaskManager (Task Manager)**
- Task lifecycle management: Create → Publish → Activate → Complete/Cancel
- State machine pattern ensures legal state transitions
- Integration with Treasury for fund escrow
- Support for pluggable Guard validation mechanism
- Task reward increase functionality (only increases, never decreases)

**SubmissionManager (Submission Manager)**
- Work submission and version management
- Multi-round review process coordination
- Strategy pattern-based automated decision making
- IPFS/Arweave content storage integration

**ReputationManager (Reputation Manager)**
- Dynamic reputation calculation and state management
- Reputation-based staking requirements
- Categorized professional skill scoring
- Time-locked unstaking mechanism

**AllowlistManager (Allowlist Manager)** 🔒
- Unified management of platform-verified Guards, Strategies, and Tokens
- Interface validation ensures only compliant contracts are added
- Batch operation support for improved management efficiency
- Prevents users from using unverified malicious contracts

**Treasury (Fund Manager)**
- Multi-purpose fund isolation management
- ETH and ERC20 token support
- Authorized access control matrix
- Emergency pause functionality

**ArbitrationManager (Arbitration Manager)**
- Dispute request and handling process
- Fee deposit and refund mechanism
- Remedial measure execution
- Decision recording and traceability

### 2.3 AllowlistManager System Architecture 🔒

AllowlistManager is the security management core of the Hermis platform, responsible for unified management and verification of all user-configurable contract parameters, ensuring only platform-audited safe contracts can be used.

#### 2.3.1 Design Goals

**Security First**
- Prevent users from using unverified malicious Guard contracts
- Prevent use of unsafe Strategy policies
- Restrict to platform-approved Tokens only

**Centralized Management**
- Unified allowlist management interface
- Consistent validation logic
- Easy platform upgrades and maintenance

**Flexibility and Efficiency**
- Support dynamic contract addition/removal
- Batch operation support
- Standardized interface validation

#### 2.3.2 Core Functions

**Guard Management**
```solidity
function allowGuard(address guard) external onlyOwner {
    // Verify Guard implements IGuard interface
    try IGuard(guard).getGuardMetadata() returns (...) {
        _allowedGuards[guard] = true;
        emit GuardAllowed(guard, msg.sender);
    } catch {
        revert InvalidAddress();
    }
}
```

**Strategy Management**
```solidity
function allowStrategy(address strategy) external onlyOwner {
    // Try to verify IAdoptionStrategy interface (optional)
    try IAdoptionStrategy(strategy).getStrategyMetadata() returns (...) {
        // Valid Adoption Strategy
    } catch {
        // May be another type of Strategy, continue to allow
    }
    _allowedStrategies[strategy] = true;
    emit StrategyAllowed(strategy, msg.sender);
}
```

**Token Management**
```solidity
function allowToken(address token) external onlyOwner {
    if (token != address(0)) {
        // Verify contract address
        uint256 codeSize;
        assembly { codeSize := extcodesize(token) }
        if (codeSize == 0) revert InvalidAddress();
    }
    _allowedTokens[token] = true;
    emit TokenAllowed(token, msg.sender);
}
```

**Task Configuration Validation**
```solidity
function validateTaskConfig(
    address submissionGuard,
    address reviewGuard,
    address adoptionStrategy,
    address rewardToken
) external view returns (bool isValid, string memory reason) {
    // Verify all parameters are in allowlist
    if (!_allowedGuards[submissionGuard]) {
        return (false, "Submission guard not allowed");
    }
    if (!_allowedGuards[reviewGuard]) {
        return (false, "Review guard not allowed");
    }
    if (!_allowedStrategies[adoptionStrategy]) {
        return (false, "Adoption strategy not allowed");
    }
    if (!_allowedTokens[rewardToken]) {
        return (false, "Reward token not allowed");
    }
    return (true, "");
}
```

#### 2.3.3 Security Features

**Interface Validation**
- Guard contracts must implement `getGuardMetadata()` method
- Strategy contracts optionally implement `getStrategyMetadata()` method
- Token must be valid contract address (or address(0) for ETH)

**Default Allowances**
- `address(0)` allowed by default as Guard (no guard)
- `address(0)` allowed by default as Token (native ETH)
- Strategy must be explicitly added, no default

**Permission Control**
- Only contract Owner can add/remove allowlist items
- Cannot disable `address(0)` as Guard and Token
- All operations emit events for tracking

#### 2.3.4 Integration Usage

**Integration in TaskManager**
```solidity
function createTask(...) external {
    // Validate task configuration
    (bool isValid, ) = allowlistManager.validateTaskConfig(
        submissionGuard,
        reviewGuard,
        adoptionStrategy,
        rewardToken
    );
    if (!isValid) revert InvalidConfiguration();

    // Create task...
}
```

**Batch Management Operations**
```solidity
// Batch add Guards
function allowGuardBatch(address[] calldata guards) external onlyOwner;

// Batch add Strategies
function allowStrategyBatch(address[] calldata strategies) external onlyOwner;

// Batch add Tokens
function allowTokenBatch(address[] calldata tokens) external onlyOwner;
```

### 2.4 Guard System Architecture 🛡️

The Guard system is the core security mechanism of the Hermis platform, providing fine-grained access control and validation logic. Adopting a layered design supporting pluggable validation strategies.

#### 2.4.1 Guard Architecture Design

```
BaseGuard (Abstract Base Class)
├── Common Interface Definition (IGuard)
├── Initialization Mechanism (Initializable)
├── Configuration Management (Configurable)
└── Metadata Management (Metadata)

Guard Type Hierarchy:
├── Global Guards
│   └── GlobalGuard - Platform-level access control
├── Reputation Guards
│   └── ReputationGuard - Reputation validation
└── Task Guards
    ├── SubmissionGuard - Submission validation
    └── ReviewGuard - Review validation
```

#### 2.4.2 GlobalGuard - Global Guard

Implements platform-level access control ensuring users meet basic participation requirements:

**Core Configuration Structure**:
```solidity
struct GlobalGuardConfig {
    uint256 minReputationForNormal;    // Minimum reputation for normal users (default: 600, i.e., 60.0)
    uint256 atRiskThreshold;           // At-risk user threshold (default: 200, i.e., 20.0)
    uint256 baseStakeAmount;           // Base stake amount (default: 1 ether)
    bool enforceStakeForAtRisk;        // Enforce staking for at-risk users
    bool allowBlacklistedUsers;        // Allow blacklisted users (default: false)
}
```

**Validation Logic Flow**:
```solidity
function validateUser(address user, bytes calldata actionData)
    external view returns (bool success, string memory reason) {

    // 1. Get user reputation info
    (uint256 reputation, DataTypes.UserStatus status, uint256 stakedAmount,,) =
        reputationManager.getUserReputation(user);

    // 2. Check user status
    if (status == DataTypes.UserStatus.BLACKLISTED && !config.allowBlacklistedUsers) {
        return (false, "User is blacklisted");
    }

    // 3. Validate reputation requirements
    if (reputation < config.minReputationForNormal) {
        // Additional stake check for at-risk users
        if (config.enforceStakeForAtRisk && stakedAmount < config.baseStakeAmount) {
            return (false, "Insufficient stake for at-risk user");
        }
    }

    // 4. Action-specific validation
    string memory action = abi.decode(actionData, (string));
    return _validateActionSpecific(user, action, reputation);
}
```

**Action-Specific Validation Rules**:
```solidity
function _validateActionSpecific(address user, string memory action, uint256 reputation)
    internal view returns (bool success, string memory reason) {

    // High-risk actions require normal user status
    if (keccak256(bytes(action)) == keccak256("PUBLISH_TASK") ||
        keccak256(bytes(action)) == keccak256("SUBMIT_WORK") ||
        keccak256(bytes(action)) == keccak256("REVIEW_SUBMISSION")) {

        if (reputation < config.minReputationForNormal) {
            return (false, "High-risk action requires normal user status");
        }
    }

    // Arbitration actions require special reputation requirements
    if (keccak256(bytes(action)) == keccak256("REQUEST_ARBITRATION")) {
        if (reputation < 500) { // 50.0
            return (false, "Arbitration requires minimum 50.0 reputation");
        }
    }

    return (true, "Global access requirements met");
}
```

#### 2.4.3 SubmissionGuard - Submission Guard

Specifically validates submission qualifications and quality requirements:

**Core Configuration Structure**:
```solidity
struct SubmissionConfig {
    uint256 minReputationScore;        // Minimum reputation requirement (default: 500, i.e., 50.0)
    bool requireCategoryExpertise;     // Require category expertise
    string requiredCategory;           // Required skill category (e.g., "development")
    uint256 minCategoryScore;          // Minimum category skill score (default: 700, i.e., 70.0)
    uint256 maxFailedSubmissions;     // Maximum failed submission count (default: 3)
    bool enforceSuccessRate;           // Enforce success rate check
    uint256 minSuccessRate;            // Minimum success rate percentage (default: 80%)
}
```

#### 2.4.4 ReviewGuard - Review Guard

Ensures reviewers have sufficient capability and authority to conduct reviews:

**Core Configuration Structure**:
```solidity
struct ReviewConfig {
    uint256 minReputationScore;        // Reviewer minimum reputation (default: 600, i.e., 60.0)
    bool requireCategoryExpertise;     // Require category expertise
    string requiredCategory;           // Review domain requirement (e.g., "development")
    uint256 minCategoryScore;          // Minimum professional skill score (default: 750, i.e., 75.0)
    uint256 minReviewCount;            // Minimum review count requirement (default: 5)
    bool enforceAccuracyRate;          // Enforce accuracy rate check
    uint256 minAccuracyRate;           // Minimum review accuracy rate (default: 85%)
}
```

### 2.5 Strategy System Architecture ⚙️

The Strategy system implements modular and pluggable design for business logic, supporting continuous platform evolution and customization needs.

#### 2.5.1 Strategy Architecture Design

```
Strategy Interface Layer:
├── IAdoptionStrategy - Adoption strategy interface
│   ├── evaluateSubmission() - Evaluate submission status
│   ├── shouldCompleteTask() - Determine task completion
│   └── getStrategyMetadata() - Get strategy metadata
└── IRewardStrategy - Reward strategy interface
    ├── calculateRewardDistribution() - Calculate reward distribution
    ├── calculateReviewerReward() - Calculate reviewer reward
    └── getRewardMetadata() - Get reward metadata

Strategy Implementation Layer:
├── Adoption Strategies
│   ├── SimpleAdoptionStrategy - Simple majority decision
│   ├── WeightedAdoptionStrategy - Weighted voting decision (planned)
│   └── TimeBasedAdoptionStrategy - Time-driven decision (planned)
└── Reward Strategies
    ├── BasicRewardStrategy - Basic proportional distribution
    ├── PerformanceRewardStrategy - Performance-based distribution (planned)
    └── DynamicRewardStrategy - Dynamic adjustment distribution (planned)
```

#### 2.5.2 SimpleAdoptionStrategy - Simple Adoption Strategy

Implements submission adoption decision mechanism based on review voting:

**Core Configuration Structure**:
```solidity
struct SimpleAdoptionConfig {
    uint256 minReviewsRequired;        // Minimum review count requirement (default: 3)
    uint256 approvalThreshold;         // Approval threshold percentage (default: 60%)
    uint256 rejectionThreshold;        // Rejection threshold percentage (default: 40%)
    uint256 expirationTime;            // Decision timeout (default: 7 days)
    bool allowTimeBasedAdoption;       // Allow timeout auto-adoption (default: false)
    uint256 autoAdoptionTime;          // Auto-adoption time (default: 0)
}
```

#### 2.5.3 BasicRewardStrategy - Basic Reward Strategy

Implements flexible reward distribution mechanism supporting reasonable revenue allocation for creators, reviewers, and platform:

**Core Configuration Structure**:
```solidity
struct BasicRewardConfig {
    uint256 creatorPercentage;         // Creator reward percentage (default: 70%)
    uint256 reviewerPercentage;        // Reviewer reward percentage (default: 20%)
    uint256 platformPercentage;        // Platform revenue percentage (default: 10%)
    uint256 accuracyBonus;             // Accurate review reward bonus (default: 20%)
    uint256 accuracyPenalty;           // Inaccurate review penalty (default: 10%)
    uint256 minReviewerReward;         // Minimum reviewer reward (default: 0)
    uint256 maxReviewerReward;         // Maximum reviewer reward (default: 0, unlimited)
}
```

### 2.6 Contract Technology Stack

**Smart Contract Development**
- Solidity ^0.8.23: Latest language features and security improvements
- OpenZeppelin: Secure contract libraries and standard implementations
- Foundry: Modern development, testing, and deployment toolchain

**Contract Security**
- ReentrancyGuard: Reentrancy attack protection
- AccessControl: Role-based permission management
- Pausable: Emergency pause mechanism
- Proxy pattern: Upgradeable contract support

**Storage and Indexing**
- IPFS: Decentralized content storage
- The Graph: On-chain data indexing
- Event logs: Contract state change tracking

**Development Tools**
- Foundry: Compilation, testing, deployment
- Slither: Static security analysis
- Mythril: Symbolic execution security testing
- Echidna: Fuzzing testing tool

---

## 3. Core Functional Modules

### 3.1 Task Management Contract (TaskManager)

**Task Creation Function**
```solidity
function createTask(
    string calldata title,              // Task title
    string calldata description,        // Detailed description
    string calldata requirements,       // Technical requirements
    string calldata category,           // Task category
    uint256 deadline,                   // Deadline
    uint256 reward,                     // Reward amount
    address rewardToken,                // Reward token address (0 for ETH)
    address submissionGuard,            // Submission guard address
    address reviewGuard,                // Review guard address
    address adoptionStrategy            // Adoption strategy address
) external returns (uint256 taskId)
```

**State Management Mechanism**
- **DRAFT**: Initial state after task creation, configuration can be modified
- **PUBLISHED**: Task publicly published, accepting collaborator bids
- **ACTIVE**: Enters active state after receiving first submission
- **COMPLETED**: Winning work determined through community review
- **CANCELLED**: Actively cancelled by publisher, reputation deducted
- **EXPIRED**: Automatically expired after deadline

### 3.2 Submission Management Contract (SubmissionManager)

**Work Submission Function**
```solidity
function submitWork(
    uint256 taskId,                  // Task ID
    string calldata contentHash      // IPFS content hash
) external returns (uint256 submissionId)
```

**Multi-Round Review Mechanism**
- **Professional Review**: Community members with relevant skills participate in reviews
- **Anonymous Review**: Reviewer identities kept secret until results announced
- **Incentive Alignment**: Accurate reviewers rewarded, incorrect reviews penalized
- **Anti-Cheating Mechanism**: Prohibit self-review and conflict-of-interest reviews

### 3.3 Reputation Scoring System

**Dynamic Reputation Calculation**
```
User Reputation = Base Score + Task Completion Bonus + Review Accuracy Bonus - Violation Penalties
```

**Reputation Factors**
- **Task Completion**: Successfully completing tasks gains +10.0 reputation
- **Accurate Review**: Review results matching consensus gains +2.0 reputation
- **Task Cancellation**: Publisher canceling task loses -5.0 reputation
- **Work Rejection**: Submitted work rejected by community loses -20.0 reputation
- **Incorrect Review**: Review results not matching consensus loses -2.0 reputation

**User Status Tiers**
- **NORMAL**: Reputation ≥ 60.0, full platform privileges
- **AT_RISK**: Reputation 10.0-59.9, restricted access, requires staking
- **BLACKLISTED**: Reputation < 10.0, severely restricted usage

### 3.4 Dispute Arbitration System

**Arbitration Types**
- **User Reputation Appeal**: Dispute reputation deductions
- **Submission Status Dispute**: Unsatisfied with work review results

**Arbitration Process**
1. **Submit Request**: Pay arbitration fee and provide evidence
2. **Arbitration Review**: Administrators review dispute content
3. **Make Decision**: Approve or reject appeal request
4. **Execute Decision**: Restore reputation or refund fees

---

## 4. Development Logic and Design Patterns

### 4.1 Architectural Design Principles

**Modular Design**
- Each contract has single responsibility for easier testing and upgrading
- Define contract interactions through interfaces, reducing coupling
- Use strategy pattern for pluggable business logic

**Extensibility**
- Guard system supports custom validation logic
- Strategy pattern supports different adoption and reward strategies
- Proxy pattern supports contract logic upgrades

**Security First**
- Reentrancy attack protection
- Strict input parameter validation
- Precise permission matrix control
- Emergency pause mechanism

### 4.2 Core Design Patterns

**State Machine Pattern**
```solidity
// Task state transition control
modifier onlyInStatus(uint256 taskId, DataTypes.TaskStatus status) {
    require(tasks[taskId].status == status, "Invalid task status");
    _;
}

function publishTask(uint256 taskId)
    external
    onlyTaskPublisher(taskId)
    onlyInStatus(taskId, DataTypes.TaskStatus.DRAFT)
{
    // State transition logic
    tasks[taskId].status = DataTypes.TaskStatus.PUBLISHED;
}
```

**Strategy Pattern**
```solidity
// Pluggable adoption strategy
interface IAdoptionStrategy {
    function checkAdoption(uint256 submissionId)
        external view returns (bool shouldAdopt, string memory reason);
}

// Different strategy implementations
contract SimpleAdoptionStrategy is IAdoptionStrategy {
    function checkAdoption(uint256 submissionId) external view override {
        // Simple strategy based on vote count and ratio
    }
}
```

---

## 5. System Integration Standards

### 5.1 Contract Interface Standardization

**Unified Interface Specifications**
```solidity
// Guard system unified interface
interface IGuard {
    function validateUser(address user, bytes calldata data)
        external view returns (bool success, string memory reason);
    function getGuardConfig() external view returns (bytes memory config);
    function updateGuardConfig(bytes calldata newConfig) external;
}

// Strategy system unified interface
interface IAdoptionStrategy {
    function evaluateSubmission(
        uint256 submissionId,
        uint256 approveCount,
        uint256 rejectCount,
        uint256 totalReviews,
        uint256 timeSinceSubmission
    ) external view returns (
        DataTypes.SubmissionStatus newStatus,
        bool shouldChange,
        string memory reason
    );
}
```

### 5.2 Third-Party Service Integration

**IPFS Content Storage Integration**
```solidity
// IPFS content hash validation
library IPFSHash {
    function isValidIPFSHash(string memory hash) internal pure returns (bool) {
        bytes memory hashBytes = bytes(hash);
        // Validate IPFS hash format (starts with Qm, 46 characters)
        return hashBytes.length == 46 &&
               hashBytes[0] == 'Q' &&
               hashBytes[1] == 'm';
    }
}
```

---

## 6. Economic Model Design

### 6.1 Multi-Token Support Architecture

**Supported Token Types**
- **ETH**: Native Ethereum as task rewards and staking assets
- **Stablecoins**: Support for mainstream stablecoins like USDC, USDT, DAI
- **ERC20 Tokens**: Any ERC20 token can be used for rewards and staking
- **Flexible Configuration**: Each task and user can choose preferred token type

**Decentralized Token Economy**
- **No Native Token**: Platform does not issue its own governance or utility token
- **Open Ecosystem**: Supports all mainstream assets in the existing cryptocurrency ecosystem
- **Lower Barriers**: Users can participate in platform activities with familiar tokens
- **Reduce Speculation**: Focus on practical value rather than token speculation

### 6.2 Incentive Mechanism Design

**Multi-Level Incentive System**
```
Direct Incentives (Task Rewards)
├── Task Completion Rewards: Winner receives reward set by task publisher
├── Review Participation Rewards: Accurate reviewers share part of reward pool
└── Reputation Boost Benefits: High reputation users enjoy platform privileges and priority

Indirect Incentives (Reputation Rewards)
├── Quality Contribution Incentives: Quality work improves reputation and platform status
├── Community Participation Incentives: Active reviewing and arbitration boosts reputation
└── Long-Term Development Incentives: Continuous contributions gain higher platform permissions
```

### 6.3 Fund Flow Model

**Treasury Fund Isolation Management**
```
Treasury Categorized Fund Management
├── Task Escrow Funds
│   ├── Winner Rewards: ~70%
│   ├── Reviewer Rewards: ~25%
│   └── Platform Fees: ~5%
├── User Staking Funds (Independently managed)
├── Arbitration Deposits (Independently managed)
└── Platform Fee Accumulation (Independent withdrawal)
```

---

## 7. Security Mechanisms

### 7.1 Smart Contract Security

**Reentrancy Attack Protection**
```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Treasury is ReentrancyGuard {
    function withdrawTaskReward(uint256 taskId, address recipient, uint256 amount)
        external
        nonReentrant
        onlyAuthorized
    {
        // Check-Effects-Interactions pattern
        require(balances[taskId] >= amount, "Insufficient balance");
        balances[taskId] -= amount;

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }
}
```

**Permission Control Matrix**
```solidity
// Role-based access control
contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private roles;

    bytes32 public constant TASK_MANAGER_ROLE = keccak256("TASK_MANAGER");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR");

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "Access denied");
        _;
    }
}
```

### 7.2 Economic Security Design

**Anti-Sybil Attack Mechanism**
- **Identity Verification**: ENS domain or social account binding
- **Staking Threshold**: New users require minimum staking amount
- **Behavior Analysis**: Detect abnormal batch operation patterns
- **Reputation Accumulation**: Reputation must be accumulated through long-term behavior

---

## 8. Smart Contract Testing System

### 8.1 Testing Architecture Design

**Testing Layer Structure**
```
Testing Pyramid
├── Integration Tests - 16 tests
│   ├── GuardStrategyIntegration.t.sol - Complete workflow tests
│   └── HermisIntegration.t.sol - End-to-end integration tests
├── Unit Tests - 165 tests
│   ├── Core Contract Tests (70 tests)
│   │   ├── TaskManager.t.sol - 15 tests
│   │   ├── SubmissionManager.t.sol - 13 tests
│   │   ├── ArbitrationManager.t.sol - 10 tests
│   │   └── AllowlistManager.t.sol - Full coverage
│   ├── Guards Test Suite (50 tests)
│   │   ├── GlobalGuard.t.sol - 18 tests
│   │   └── SubmissionGuard.t.sol - 16 tests
│   └── Strategies Test Suite (45 tests)
│       ├── SimpleAdoptionStrategy.t.sol - 24 tests
│       └── BasicRewardStrategy.t.sol - 24 tests
└── Performance Tests (Gas Optimization Tests)

Total: 181 comprehensive tests, 100% pass rate (181/181) ✅
```

### 8.2 Testing Tools and Frameworks

**Foundry Testing Framework Configuration**
```toml
# foundry.toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
test = "test"
gas_reports = ["*"]

[profile.ci]
fuzz = { runs = 10000 }
invariant = { runs = 1000 }
```

### 8.3 Testing Quality Metrics

**Test Coverage Statistics**
```
Contract Feature Coverage:
├── AllowlistManager: 100% feature coverage
├── Guards System: 90%+ feature coverage
├── Strategies System: 95%+ feature coverage
└── Integration Tests: 85%+ workflow coverage
```

---

## 9. Contract Deployment and Operations

### 9.1 Deployment Architecture

**Multi-Environment Deployment Strategy**
```
Development Environment
├── Local Anvil network
├── Fast iteration testing
└── Development team internal use

Testing Environment (Testnet)
├── Sepolia testnet
├── Feature completeness verification
└── Community beta testing

Production Environment (Mainnet)
├── Ethereum mainnet
├── Complete security audit
└── Multi-signature control
```

### 9.2 Upgrade Management

**Contract Upgrade Strategy**
```solidity
// Transparent proxy upgrade pattern
contract HermisUpgradeManager {
    ProxyAdmin public proxyAdmin;
    mapping(string => address) public proxies;

    function upgradeContract(
        string memory contractName,
        address newImplementation
    ) external onlyOwner {
        address proxy = proxies[contractName];
        require(proxy != address(0), "Proxy not found");

        // Pre-upgrade validation
        require(validateUpgrade(proxy, newImplementation), "Invalid upgrade");

        // Execute upgrade
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(proxy)),
            newImplementation
        );
    }
}
```

---

## 10. Technical Innovation Highlights

### 10.1 Architectural Innovation

**Interface-Contract Separation Architecture**
- All events, errors, and struct definitions in interfaces
- Implementation contracts obtain standardized definitions through inheritance
- Facilitates contract upgrades and third-party integration
- Improves code reusability and maintainability

**AllowlistManager Security Management Innovation** 🔒
- Unified allowlist management: Centralized management of Guards, Strategies, and Tokens
- Interface validation mechanism: Automatically verifies contracts implement required interfaces
- Batch operation support: Improves management efficiency
- Prevents malicious contracts: Only allows platform-verified safe contracts

**Deep Application of Strategy Pattern**
- Adoption strategies: Configurable submission approval conditions
- Reward strategies: Flexible revenue distribution mechanism
- Guard strategies: Composable access control validation
- Supports runtime strategy replacement and composition

### 10.2 Business Model Innovation

**Dynamic Reputation Staking Mechanism**
```
Required Stake = Base Stake × (1000 - Reputation×10) / 1000
```
- Higher reputation means lower staking requirements
- Incentivizes users to maintain good reputation
- Effectively prevents malicious behavior

**Multi-Level Peer Review System**
- Professional skill-matched reviewer selection
- Historical tracking of review quality
- Incentivizes accurate reviews, penalizes incorrect judgments

### 10.3 Technical Implementation Innovation

**Gas-Optimized Data Structures**
```solidity
// Compact struct design
struct Task {
    address publisher;          // 20 bytes
    uint96 reward;             // 12 bytes - shares slot with publisher
    uint32 deadline;           // 4 bytes
    uint32 createdAt;          // 4 bytes
    TaskStatus status;         // 1 byte - three fields share one slot
}
```

**Testable Smart Contract Design**
```solidity
// Testable time handling
contract TimeProvider {
    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp;
    }
}

// Mock time provider in tests
contract MockTimeProvider is TimeProvider {
    uint256 private mockTime;

    function setMockTime(uint256 time) external {
        mockTime = time;
    }
}
```

---

## Smart Contract Architecture Summary

The Hermis Protocol smart contract system serves as the core infrastructure of a decentralized crowdsourcing collaboration platform, achieving a completely decentralized task collaboration ecosystem through innovative contract architecture design and advanced blockchain technology.

### 🏗️ Contract Architecture Advantages

**Layered Modular Design**
- **Core Business Layer**: Core contracts like TaskManager, SubmissionManager, ReputationManager
- **Access Control Layer**: Security guards like GlobalGuard, SubmissionGuard, ReviewGuard
- **Strategy Execution Layer**: Pluggable strategies like SimpleAdoptionStrategy, BasicRewardStrategy
- **Infrastructure Layer**: Support services like Treasury, HermisSBT, ArbitrationManager

**Guard System Innovation** 🛡️
- **Layered Validation**: Progressive security control from Global→Reputation→Task-specific
- **Configurability**: Each guard supports flexible parameter configuration and runtime updates
- **Modularity**: Different guard types focus on specific validation logic and business scenarios
- **Standardized Interface**: Unified IGuard interface supports third-party guard extensions

**Strategy System Innovation** ⚙️
- **Pluggable Architecture**: Supports dynamic replacement of different strategy implementations
- **Business Separation**: Separates complex decision logic from core contracts
- **Algorithm Flexibility**: Supports different adoption strategies and reward distribution algorithms
- **Extensibility**: Easy to add new strategy types and custom business rules

### 📊 Project Achievement Statistics

**Code Quality Metrics**
- **Contract Count**: 16+ core smart contracts (including AllowlistManager)
- **Lines of Code**: 6000+ Solidity code
- **Test Coverage**: 100% test pass rate (181/181 tests) ✅
- **Security Level**: Multi-layer security protection, zero critical vulnerabilities

**Ecosystem Compatibility**
- **Standard Compliance**: ERC20, ERC721, EIP-1967 standard compliance
- **Cross-Chain Support**: Supports Ethereum mainnet and Layer 2 deployment
- **Third-Party Integration**: Standardized interfaces support DApp and service integration
- **Open Source License**: MIT license supports community contribution and forking

The Hermis Protocol smart contract system represents an important breakthrough of blockchain technology in the crowdsourcing collaboration field, providing a solid technical foundation for building a decentralized digital economy ecosystem.
