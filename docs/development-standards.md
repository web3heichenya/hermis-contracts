# Smart Contract Development Standards

## Table of Contents
- [Overview](#overview)
- [Code Style Guidelines](#code-style-guidelines)
- [Naming Conventions](#naming-conventions)
- [Contract Structure](#contract-structure)
- [Function Guidelines](#function-guidelines)
- [Documentation Standards](#documentation-standards)
- [Security Guidelines](#security-guidelines)
- [Testing Standards](#testing-standards)
- [Gas Optimization Guidelines](#gas-optimization-guidelines)

## Overview

This document defines comprehensive coding standards for smart contract development. These standards ensure code consistency, readability, maintainability, and security across all smart contracts.

### Compliance Requirements

- **MUST**: All new code must follow these standards
- **SHOULD**: Existing code should be refactored to meet standards when modified
- **MAY**: Deviations are allowed only with explicit team approval and documentation

## Code Style Guidelines

### File Organization

#### SPDX License and Pragma
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
```

**Requirements**:
- MUST use MIT license identifier
- MUST use Solidity version 0.8.23 or compatible
- MUST include exact version (^0.8.23)

#### Import Organization
```solidity
// 1. OpenZeppelin imports
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// 2. Solady imports  
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import {LibString} from "solady/utils/LibString.sol";

// 3. Internal interfaces
import {IContractA} from "../interfaces/IContractA.sol";
import {IContractB} from "../interfaces/IContractB.sol";

// 4. Internal libraries
import {Constants} from "../libraries/Constants.sol";
```

**Requirements**:
- MUST group imports by source (external libraries, interfaces, libraries)
- MUST use named imports `{Contract}` instead of wildcard imports
- MUST sort imports alphabetically within each group
- MUST separate groups with blank lines

### Formatting Standards

#### Line Length and Indentation
```solidity
// GOOD: Under 120 characters
function longFunctionName(uint256 parameter1, uint256 parameter2) external view returns (bool);

// BAD: Over 120 characters
function veryLongFunctionNameThatExceedsTheRecommendedLineLengthAndShouldBeReformatted(uint256 parameter1, uint256 parameter2, uint256 parameter3) external view returns (bool);
```

**Requirements**:
- MUST keep lines under 120 characters
- MUST use 4-space indentation (no tabs)
- MUST break long function signatures across multiple lines
- MUST align parameters when wrapping

#### Bracket Placement
```solidity
// GOOD: Opening bracket on same line
contract Example {
    function example() external {
        if (condition) {
            // code here
        }
    }
}

// BAD: Opening bracket on new line
contract Example 
{
    function example() external 
    {
        if (condition) 
        {
            // code here
        }
    }
}
```

## Naming Conventions

### Contract Naming

#### Contract Names
```solidity
// GOOD: PascalCase for contracts
contract TokenContract {}
contract ManagerContract {}
contract UtilityContract {}

// BAD: Other naming styles
contract token_contract {}  // snake_case
contract tokenContract {}   // camelCase
```

**Requirements**:
- MUST use PascalCase for contract names
- MUST use descriptive, business-focused names
- SHOULD include the primary function or domain (e.g., "Token", "Manager", "Registry")

#### Interface Names
```solidity
// GOOD: Interface prefix
interface IExampleContract {}
interface IManagerContract {}
interface IRegistryContract {}

// ACCEPTABLE: Without prefix if clearly an interface
interface ExampleContractInterface {}
```

**Requirements**:
- MUST prefix interfaces with "I"
- MUST use PascalCase after prefix
- MUST match corresponding implementation name

#### Library Names
```solidity
// GOOD: Library naming
library Constants {}
library UtilityLib {}
library MathUtils {}

// BAD: Library naming
library constants {}  // camelCase
library CONSTANTS {} // SCREAMING_SNAKE_CASE
```

### Variable Naming

#### State Variables
```solidity
// GOOD: Private variables with underscore prefix
contract Example {
    uint256 private _nextTokenId;
    mapping(address => bool) private _hasMinted;
    ISVGRenderer private _svgRenderer;
    
    // Public/external variables without prefix
    uint256 public totalSupply;
    address public immutable TREASURY;
}
```

**Requirements**:
- MUST use underscore prefix for private variables (`_variableName`)
- MUST use camelCase for variable names
- MUST use SCREAMING_SNAKE_CASE for constants and immutable variables
- SHOULD use descriptive names that indicate purpose

#### Function Parameters and Local Variables
```solidity
// GOOD: Clear, descriptive names
function exampleFunction(
    address recipient,
    Constants.ItemType itemType,
    uint256 randomSeed
) external returns (uint256 itemId) {
    uint256 nextId = _nextItemId;
    Constants.Item memory newItem = Constants.Item({
        // ... initialization
    });
}

// BAD: Unclear, abbreviated names
function exampleFunction(address r, uint256 c, uint256 s) external returns (uint256 t) {
    uint256 n = _nextItemId;
    // unclear variable names
}
```

**Requirements**:
- MUST use camelCase for parameters and local variables
- MUST use descriptive names (no single-letter variables except loop counters)
- SHOULD avoid abbreviations unless universally understood
- MAY use short names for temporary variables in very short scopes

#### Mapping Variables
```solidity
// GOOD: Descriptive mapping names
mapping(uint256 => Constants.Item) private _items;
mapping(address => bool) private _hasProcessed;
mapping(bytes32 => ActionRequest) private _actionRequests;
mapping(uint256 => bytes32) private _itemToPendingRequest;

// BAD: Generic mapping names
mapping(uint256 => Constants.Item) private _data;
mapping(address => bool) private _flags;
```

**Requirements**:
- MUST use descriptive names that indicate both key and value types
- SHOULD use format `_keyTypeToValueType` for complex mappings
- MUST follow private variable underscore convention

### Enum and Struct Naming

#### Enum Types and Values
```solidity
// GOOD: PascalCase for enum types, SCREAMING_SNAKE_CASE for values
enum ItemStatus {
    PENDING,
    ACTIVE,
    COMPLETED
}

enum Priority {
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL
}
```

**Requirements**:
- MUST use PascalCase for enum type names
- MUST use SCREAMING_SNAKE_CASE for enum values
- SHOULD use descriptive, domain-specific names
- MUST be singular for the enum type name

#### Struct Naming
```solidity
// GOOD: PascalCase for struct names, camelCase for fields
struct ItemData {
    uint32 value1;
    uint32 value2;
    uint32 value3;
    uint32 value4;
    uint16 parameter1;
    uint16 parameter2;
}

struct ActionRequest {
    uint256 itemId;
    address requester;
    uint64 requestTime;
    bool fulfilled;
}
```

**Requirements**:
- MUST use PascalCase for struct names
- MUST use camelCase for struct field names
- SHOULD group related fields together
- SHOULD order fields by size for gas optimization when possible

### Function Naming

#### Function Names
```solidity
// GOOD: Descriptive function names
function createItem() external payable returns (uint256 itemId) {}
function executeAction(uint256 itemId, uint256 configId) external payable {}
function getItemData(uint256 itemId) external view returns (Constants.ItemData memory) {}
function isActionAvailable(uint256 itemId) external view returns (bool available, uint256 timeLeft) {}

// Internal functions with underscore prefix
function _generateRandomValue(uint256 seed) internal view returns (uint256) {}
function _validateActionEligibility(uint256 itemId) internal view {}
function _updateItemData(Constants.ItemData storage data) internal {}
```

**Requirements**:
- MUST use camelCase for function names
- MUST prefix internal/private functions with underscore (`_functionName`)
- MUST use descriptive, action-oriented names
- SHOULD start with verb (get, set, check, validate, execute, etc.)
- MUST clearly indicate return type in name for view functions

#### Modifier Names
```solidity
// GOOD: Descriptive modifier names
modifier onlyItemOwner(uint256 itemId) {}
modifier validItem(uint256 itemId) {}
modifier onlyActionCoordinator() {}

// BAD: Generic modifier names
modifier onlyAuthorized() {}  // Too generic
modifier check(uint256 id) {} // Not descriptive
```

**Requirements**:
- MUST use camelCase for modifier names
- SHOULD start with condition type (only, valid, ensure, require)
- MUST be descriptive about what they validate

### Event Naming

```solidity
// GOOD: PascalCase event names with descriptive parameters
event ItemCreated(address indexed owner, uint256 indexed itemId, string itemType);
event ActionCompleted(uint256 indexed itemId, uint256 indexed actionId, uint256 indexed actionType);
event DataUpdated(uint256 indexed itemId, Constants.ItemData newData);

// Parameter naming
event Transfer(address indexed from, address indexed to, uint256 indexed itemId);
```

**Requirements**:
- MUST use PascalCase for event names
- MUST use past tense verbs (Minted, Completed, Updated)
- MUST index primary keys and frequently queried parameters
- SHOULD limit to 3 indexed parameters maximum
- MUST use descriptive parameter names

## Contract Structure

### Interface-Contract Architecture

When a contract has a corresponding interface, follow these **MANDATORY** architectural rules:

#### Events, Errors, and Structs Placement
```solidity
// CORRECT: Interface defines all shared elements
interface IItemManager {
    // Custom errors
    error ItemNotFound(uint256 itemId);
    error InvalidItemDeadline(uint256 deadline);

    // Events
    event ItemCreated(uint256 indexed itemId, address indexed creator);
    event ItemCompleted(uint256 indexed itemId, uint256 submissionId);

    // Structs (if needed in interface)
    struct ItemInfo {
        uint256 id;
        address creator;
        string title;
    }

    // Function signatures
    function createItem(string calldata title) external returns (uint256);
}

// Contract inherits interface and uses defined elements
contract ItemManager is IItemManager {
    // NEVER re-define errors, events, or structs here
    // Use inherited ones directly:

    function createItem(string calldata title) external returns (uint256) {
        if (bytes(title).length == 0) revert InvalidItemTitle(title); // ✓ Uses interface error
        emit ItemCreated(itemId, msg.sender); // ✓ Uses interface event
    }
}
```

#### Architecture Rules
- **MUST** define all `errors` in the interface
- **MUST** define all `events` in the interface
- **MUST** define all `structs` used in function signatures in the interface
- **MUST NOT** re-define these in implementing contracts
- **MUST** use inherited definitions directly in implementations
- **MAY** define implementation-specific structs in contract if not part of interface

#### Benefits
- Single source of truth for contract API
- Prevents definition duplication
- Ensures interface-implementation consistency
- Enables proper event filtering and error handling
- Improves code maintainability

### Required Contract Organization

All contracts MUST follow this exact structure:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===
[Import statements organized by groups]

/// @title ContractName
/// @notice Brief description of contract purpose
/// @author Development Team
contract ContractName is ParentContract {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Library using statements]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Error definitions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Event definitions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [State variables - mutable]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Constants and immutable variables]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Modifier definitions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Constructor]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [External/public state-changing functions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Owner/admin only functions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [External/public view/pure functions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Internal functions]

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    [Private functions]
}
```

### Section Headers

**MUST** use the exact decorative headers shown above for each section:
- Headers provide visual separation and consistent structure
- All sections must be present even if empty
- Order must be maintained exactly as specified

### Function Ordering Within Sections

#### PUBLIC UPDATE FUNCTIONS Section
```solidity
// Order by importance/frequency of use:
// 1. Core business functions first
function create() external payable {}
function executeAction() external payable {}

// 2. Coordinator interaction functions
function updateItemDataFromCoordinator() external {}
function updateItemStatusFromCoordinator() external {}

// 3. Less frequently used functions
function setItemName() external {}
```

#### PUBLIC READ FUNCTIONS Section  
```solidity
// Order by importance/frequency of use:
// 1. Primary getters
function getItem() external view returns (Constants.Item memory) {}
function totalSupply() external view returns (uint256) {}

// 2. Utility getters
function getItemName() external view returns (string memory) {}
function isActionAvailable() external view returns (bool, uint256) {}

// 3. Administrative getters
function getConfiguration() external view returns (address) {}
```

## Function Guidelines

### Function Signature Structure

#### Parameter Organization
```solidity
// GOOD: Logical parameter grouping and typing
function executeAction(
    uint256 itemId,            // Primary entity ID
    uint256 configId,          // Configuration parameter
    uint32 gasLimit            // Technical parameter
) external payable validItem(itemId) onlyItemOwner(itemId) nonReentrant {
    // function body
}

// BAD: Poor parameter organization
function executeAction(uint32 gasLimit, uint256 itemId, uint256 configId) external payable {}
```

**Requirements**:
- MUST group related parameters together
- MUST put primary entity IDs first (itemId, recordId, etc.)
- MUST put configuration parameters next
- MUST put technical parameters last (gasLimit, deadline, etc.)
- MUST use specific types (uint32, uint64) instead of uint256 when appropriate

#### Modifier Ordering
```solidity
// GOOD: Logical modifier order
function someFunction(
    uint256 itemId
) external payable validItem(itemId) onlyItemOwner(itemId) nonReentrant {
    // Validation → Authorization → Reentrancy Protection
}

// BAD: Illogical modifier order
function someFunction(uint256 itemId) external nonReentrant onlyItemOwner(itemId) validItem(itemId) {}
```

**Requirements**:
- MUST order modifiers logically: validation → authorization → protection
- MUST place `payable` immediately after visibility
- MUST place security modifiers (`nonReentrant`) last

#### Return Value Handling
```solidity
// GOOD: Named return values for clarity
function isActionAvailable(
    uint256 itemId
) external view validItem(itemId) returns (bool available, uint256 timeLeft) {
    ActionAvailabilityCheck memory check = _performActionAvailabilityCheck(itemId);
    return (check.available, check.timeLeft);
}

// ACCEPTABLE: Unnamed returns for single values
function totalSupply() external view returns (uint256) {
    unchecked {
        return _nextTokenId - 1;
    }
}
```

**Requirements**:
- MUST use named return values for multiple returns
- SHOULD use named return values for complex single returns
- MAY use unnamed returns for simple single values
- MUST provide clear variable names that indicate purpose

### Function Implementation Patterns

#### Input Validation
```solidity
function setItemName(uint256 itemId, string calldata name)
    external validItem(itemId) onlyItemOwner(itemId) {
    // 1. Input validation (beyond modifiers)
    bytes memory nameBytes = bytes(name);
    if (nameBytes.length == 0 || nameBytes.length > 32) {
        revert InvalidItemName();
    }

    // 2. State changes
    _customItemNames[itemId] = name;

    // 3. Event emission
    emit ItemNameSet(itemId, msg.sender, name);
}
```

**Requirements**:
- MUST validate all inputs thoroughly
- MUST use custom errors instead of `require` statements
- MUST validate beyond what modifiers check
- MUST fail fast on invalid inputs

#### State Change Patterns
```solidity
function executeAction(uint256 itemId, uint256 configId, uint32 gasLimit)
    external payable validItem(itemId) onlyItemOwner(itemId) nonReentrant {
    Constants.Item storage item = _items[itemId];

    // 1. Read current state
    uint256 currentActions = item.totalActions;

    // 2. Validate preconditions
    _validateActionEligibility(item, itemId);
    _validateActionPayment(itemId, configId, gasLimit);

    // 3. Update state BEFORE external calls
    unchecked {
        ++item.totalActions;
    }
    item.lastActionTime = uint64(block.timestamp);

    // 4. External calls last
    ACTION_COORDINATOR.initiateActionAndRequestAuto{value: msg.value}(
        itemId, msg.sender, configId, gasLimit
    );
}
```

**Requirements**:
- MUST follow Checks-Effects-Interactions pattern
- MUST update state before external calls
- MUST use storage references to avoid multiple SLOADs
- MUST use `unchecked` for safe arithmetic operations

#### Error Handling
```solidity
// GOOD: Specific error with context
error InsufficientPayment(uint256 required, uint256 provided);

function create() external payable {
    if (msg.value < Constants.CREATION_PRICE) {
        revert InsufficientPayment(Constants.CREATION_PRICE, msg.value);
    }
}

// BAD: Generic error without context
error InvalidInput();

function create() external payable {
    require(msg.value >= Constants.CREATION_PRICE, "Insufficient payment");
}
```

**Requirements**:
- MUST use custom errors instead of `require` with string messages
- MUST provide specific error types for different failure modes
- SHOULD include relevant parameters in error data
- MUST use descriptive error names

## Documentation Standards

### Contract-Level Documentation

```solidity
/// @title ExampleContract
/// @notice Example NFT contract with dynamic on-chain metadata and action system
/// @dev This contract implements ERC721 with additional mechanics including:
///      - Action execution system with cooldowns
///      - Dynamic data system
///      - ERC-6551 token-bound account integration
///      - Hook system integration for extensibility
/// @author Development Team
contract ExampleContract is ERC721, Ownable, ReentrancyGuard, IExampleContract {
```

**Requirements**:
- MUST include `@title` with contract name
- MUST include `@notice` with user-facing description
- SHOULD include `@dev` with technical implementation details
- MUST include `@author` as "Development Team"
- SHOULD list key features or capabilities in `@dev`

### Function Documentation

```solidity
/// @notice Execute action for an item
/// @dev This function initiates the complete action execution:
///      1. Validates action eligibility (cooldown, status, no pending requests)
///      2. Validates payment matches configuration requirements
///      3. Updates item state (totalActions, lastActionTime)
///      4. Initiates action through ActionCoordinator
/// @param itemId Item ID to execute action on
/// @param configId Configuration ID to use
/// @param gasLimit Gas limit for the external call
/// @custom:security This function is protected against reentrancy and validates ownership
/// @custom:economy Requires payment of execution fees, updates on success only
function executeAction(
    uint256 itemId,
    uint256 configId,
    uint32 gasLimit
) external payable validItem(itemId) onlyItemOwner(itemId) nonReentrant {
```

**Requirements**:
- MUST include `@notice` with user-facing description
- SHOULD include `@dev` with implementation details for complex functions
- MUST document all parameters with `@param`
- MUST document return values with `@return` (if any)
- SHOULD include custom tags for security/economic considerations
- MAY include `@custom:` tags for additional context

### Event Documentation

```solidity
/// @notice Emitted when a new item is created
/// @param owner The address that owns the newly created item
/// @param itemId The item ID of the newly created item
/// @param itemType The type of the item (e.g., "TypeA", "TypeB")
event ItemCreated(address indexed owner, uint256 indexed itemId, string itemType);
```

**Requirements**:
- MUST include `@notice` with description of when event is emitted
- MUST document all parameters with `@param`
- SHOULD explain the meaning/format of complex parameters

### Error Documentation

```solidity
/// @notice Error thrown when insufficient payment is provided for an operation
/// @param required The required payment amount in wei
/// @param provided The actual payment amount provided in wei
error InsufficientPayment(uint256 required, uint256 provided);

/// @notice Error thrown when attempting to execute action on item that is not ready
/// @param timeLeft The number of seconds until the item can execute action again
error ActionNotReady(uint256 timeLeft);
```

**Requirements**:
- MUST include `@notice` with description of error condition
- MUST document all error parameters with `@param`
- SHOULD explain how to avoid or resolve the error condition

## Security Guidelines

### Access Control Patterns

#### Modifier-Based Protection
```solidity
/// @notice Modifier to ensure only the token owner can call the function
/// @param tokenId Token ID to check ownership for
modifier onlyTokenOwner(uint256 tokenId) {
    if (ownerOf(tokenId) != msg.sender) revert UnauthorizedAccess();
    _;
}

/// @notice Modifier to ensure the item exists
/// @param itemId Item ID to validate
modifier validItem(uint256 itemId) {
    if (!_exists(itemId)) revert InvalidItemId(itemId);
    _;
}
```

**Requirements**:
- MUST use modifiers for repeated access control logic
- MUST revert with custom errors, not require statements
- MUST validate parameters thoroughly
- SHOULD use specific error types for different failure modes

#### Authorization Levels
```solidity
// Level 1: Public functions with validation
function executeAction() external payable validItem(itemId) onlyItemOwner(itemId) {}

// Level 2: Coordinator-only functions
function updateItemDataFromCoordinator() external onlyActionCoordinator {}

// Level 3: Admin-only functions
function setConfiguration() external onlyOwner {}
```

**Requirements**:
- MUST use appropriate authorization level for each function
- MUST NOT allow bypassing of authorization checks
- SHOULD minimize admin functions and clearly document their purpose

### Reentrancy Protection

#### ReentrancyGuard Usage
```solidity
// GOOD: Proper reentrancy protection
function create() external payable nonReentrant returns (uint256 itemId) {
    // State changes before external calls
    itemId = _nextItemId;
    unchecked {
        ++_nextItemId;
    }
    _hasCreated[msg.sender] = true;

    // ERC721 mint (external call)
    _mint(msg.sender, itemId);

    // External calls last
    (bool success, ) = address(TREASURY).call{value: Constants.TREASURY_FEE}("");
    if (!success) revert InsufficientTreasuryFunds();
}
```

**Requirements**:
- MUST use `nonReentrant` modifier for all functions making external calls
- MUST update state before external calls (Checks-Effects-Interactions)
- MUST handle external call failures appropriately
- SHOULD minimize external calls within protected functions

### Input Validation

#### Comprehensive Validation
```solidity
function setItemName(uint256 itemId, string calldata name)
    external validItem(itemId) onlyItemOwner(itemId) {
    // String validation
    bytes memory nameBytes = bytes(name);
    if (nameBytes.length == 0 || nameBytes.length > 32) {
        revert InvalidItemName();
    }

    // Additional validation for special characters, profanity, etc.
    if (_containsInvalidCharacters(nameBytes)) {
        revert InvalidItemName();
    }

    _customItemNames[itemId] = name;
    emit ItemNameSet(itemId, msg.sender, name);
}
```

**Requirements**:
- MUST validate all user inputs thoroughly
- MUST check string lengths and formats
- MUST validate numeric ranges and boundaries
- SHOULD validate business logic constraints

### Integer Overflow/Underflow Protection

#### Safe Arithmetic
```solidity
// GOOD: Use unchecked when overflow is impossible
function totalSupply() external view returns (uint256) {
    unchecked {
        return _nextTokenId - 1;  // _nextTokenId starts at 1, so this is safe
    }
}

// GOOD: Use checked arithmetic for user inputs
function calculateFee(uint256 baseAmount, uint256 multiplier) internal pure returns (uint256) {
    return baseAmount * multiplier;  // Let Solidity 0.8+ check for overflow
}

// GOOD: Manual overflow checking when needed
function safeMath(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 result = a + b;
    if (result < a) revert("Overflow");
    return result;
}
```

**Requirements**:
- MUST use `unchecked` blocks only when overflow is mathematically impossible
- MUST rely on Solidity 0.8+ automatic overflow checking for user inputs
- SHOULD add explicit comments explaining why overflow is impossible in `unchecked` blocks
- MUST NOT use `unchecked` for user-controlled arithmetic

### Hook System Development

#### Hook Implementation Standards
```solidity
// GOOD: Proper hook implementation with error handling
contract CustomAnalyticsHook is IHook {
    function execute(
        IHookRegistry.HookPhase phase,
        bytes calldata data
    ) external override {
        // Handle specific phases
        if (phase == IHookRegistry.HookPhase.AFTER_ITEM_CREATED) {
            _handleItemCreated(data);
        } else if (phase == IHookRegistry.HookPhase.HERO_ATTRIBUTE_UPDATED) {
            _handleAttributeUpdate(data);
        }
        // Add other phase handlers as needed
    }
    
    function _handleItemCreated(bytes calldata data) internal {
        try this._decodeItemCreatedData(data) {
            // Process item created data safely
        } catch {
            // Log error but don't revert
            emit HookExecutionFailed("Failed to decode item created data");
        }
    }
}
```

#### Available Hook Phases and Data Formats
```solidity
enum HookPhase {
    BEFORE_ITEM_CREATION,     // data: abi.encode(address creator)
    AFTER_ITEM_CREATED,       // data: abi.encode(itemId, typeId, owner, account)
    BEFORE_ACTION_EXECUTION,  // data: abi.encode(requestId, itemId, configId, randomSeed)
    AFTER_ACTION_EXECUTED,    // data: abi.encode(actionType, result, requester, actionId, itemId)
    ACTION_INITIATION,        // data: abi.encode(requestId, itemId, configId, requester)
    ITEM_STATUS_CHANGED,      // data: abi.encode(itemId, newStatus)
    ITEM_DATA_UPDATED         // data: abi.encode(itemId, data)
}
```

#### Hook Security Requirements
- MUST implement proper error handling and never revert unexpectedly
- MUST respect gas limits set during hook registration
- MUST validate input data format before processing
- SHOULD emit events for debugging and monitoring
- MUST NOT modify core game state directly
- SHOULD use minimal gas for execution
- MUST NOT perform external calls to untrusted contracts
- SHOULD implement circuit breakers for critical failures

#### Hook Registration Best Practices
```solidity
// Register hook with appropriate gas limit and priority
hookRegistry.registerHook(
    IHookRegistry.HookPhase.AFTER_ITEM_CREATED,
    address(analyticsHook),
    100, // priority (lower = higher priority)
    50000 // gas limit
);
```

**Requirements**:
- MUST set reasonable gas limits based on hook complexity
- SHOULD use priority system to order hook execution
- MUST test hook execution under various conditions
- SHOULD implement hook deactivation mechanisms
- MUST document hook behavior and data requirements

## Testing Standards

### Test Structure Organization

#### Test File Naming
```
test/
├── unit/                           # Unit tests for individual functions
│   ├── ExampleContract.t.sol
│   ├── ActionCoordinator.t.sol
│   └── ActionEffects.t.sol
├── integration/                    # Multi-contract interaction tests
│   ├── ActionHandling.t.sol
│   ├── StatusTransition.t.sol
│   └── ERC6551Integration.t.sol
├── security/                       # Security-focused tests
│   ├── ReentrancyTests.t.sol
│   ├── EconomicAttacks.t.sol
│   └── AccessControl.t.sol
└── gas/                           # Gas optimization tests
    ├── GasOptimization.t.sol
    └── BatchOperations.t.sol
```

#### Test Contract Structure
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ExampleContract} from "../src/core/ExampleContract.sol";

/// @title ExampleContractTest
/// @notice Comprehensive tests for ExampleContract
contract ExampleContractTest is Test {
    // Test constants
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    uint256 constant CREATION_PRICE = 0.00033 ether;

    // Contract instances
    ExampleContract public exampleContract;
    
    // Test setup
    function setUp() public {
        // Deploy and initialize contracts
    }
    
    // === MINT TESTS ===
    
    function testMint_Success() public {
        // Test successful minting
    }
    
    function testMint_RevertWhenAlreadyMinted() public {
        // Test revert conditions
    }
    
    // === FORGE TESTS ===
    
    function testAction_Success() public {
        // Test successful action execution
    }
    
    // === FUZZ TESTS ===
    
    function testFuzz_MintWithDifferentPayments(uint256 payment) public {
        // Fuzz testing
    }
}
```

### Test Coverage Requirements

#### Function Coverage
**MUST achieve minimum 95% line coverage for all contracts**

**MUST test all function paths**:
- Success cases
- All revert conditions  
- Edge cases and boundary conditions
- Access control restrictions

#### Test Categories

##### 1. Unit Tests
```solidity
function testMint_Success() public {
    vm.deal(ALICE, 1 ether);
    vm.prank(ALICE);

    uint256 itemId = exampleContract.create{value: CREATION_PRICE}();

    assertEq(itemId, 1);
    assertEq(exampleContract.ownerOf(itemId), ALICE);
    assertEq(exampleContract.totalSupply(), 1);
    assertTrue(exampleContract.hasCreated(ALICE));
}

function testMint_RevertWhenInsufficientPayment() public {
    vm.deal(ALICE, 1 ether);
    vm.prank(ALICE);
    
    vm.expectRevert(
        abi.encodeWithSelector(
            IExampleContract.InsufficientPayment.selector,
            CREATION_PRICE,
            CREATION_PRICE - 1
        )
    );
    exampleContract.create{value: CREATION_PRICE - 1}();
}
```

##### 2. Integration Tests
```solidity
function testCompleteActionFlow() public {
    // 1. Create item
    uint256 itemId = _createItemFor(ALICE);

    // 2. Execute action
    vm.deal(ALICE, 1 ether);
    vm.prank(ALICE);
    exampleContract.executeAction{value: 0.01 ether}(itemId, 1, 100000);

    // 3. Verify external request
    // 4. Fulfill external request
    // 5. Verify action completion
}
```

##### 3. Security Tests
```solidity
function testReentrancy_CannotReenterCreate() public {
    ReentrantAttacker attacker = new ReentrantAttacker(exampleContract);
    vm.deal(address(attacker), 1 ether);

    vm.expectRevert("ReentrancyGuard: reentrant call");
    attacker.attack();
}
```

##### 4. Fuzz Tests
```solidity
function testFuzz_AttributeModification(
    uint256 tokenId,
    uint8 attributeIndex, 
    uint32 value
) public {
    tokenId = bound(tokenId, 1, 1000);
    attributeIndex = uint8(bound(attributeIndex, 0, 9));
    value = uint32(bound(value, 1, 10000));
    
    // Test attribute modification with random valid inputs
}
```

### Test Helper Functions

#### Common Test Utilities
```solidity
/// @notice Helper to create item for specific address
function _createItemFor(address user) internal returns (uint256 itemId) {
    vm.deal(user, 1 ether);
    vm.prank(user);
    return exampleContract.create{value: CREATION_PRICE}();
}

/// @notice Helper to advance time for testing cooldowns
function _advanceTime(uint256 seconds_) internal {
    vm.warp(block.timestamp + seconds_);
}

/// @notice Helper to setup oracle mock responses
function _mockOracleResponse(bytes32 requestId, uint256 randomSeed) internal {
    vm.mockCall(
        address(oracle),
        abi.encodeWithSelector(IOracle.fulfillRandomness.selector),
        abi.encode(randomSeed)
    );
}
```

**Requirements**:
- MUST create reusable helper functions for common test setup
- SHOULD mock external dependencies consistently
- MUST use descriptive helper function names
- SHOULD document complex test helper logic

## Gas Optimization Guidelines

### Storage Optimization

#### Struct Packing
```solidity
// GOOD: Packed struct (fits in 2 storage slots)
struct Item {
    address itemBoundAccount;    // 20 bytes (slot 1)
    uint64 lastActionTime;      // 8 bytes  (slot 1)
    uint32 totalActions;        // 4 bytes  (slot 1)
    uint64 creationTime;        // 8 bytes  (slot 2)
    ItemType typeId;            // 1 byte   (slot 2)
    ItemStatus status;          // 1 byte   (slot 2)
    ItemData data;              // 30 bytes (slot 2)
} // Total: 72 bytes = 3 slots

// BAD: Unpacked struct (uses 6 storage slots)
struct ItemBad {
    uint256 totalActions;        // 32 bytes (slot 1)
    address itemBoundAccount;    // 32 bytes (slot 2)
    uint256 lastActionTime;      // 32 bytes (slot 3)
    uint256 creationTime;        // 32 bytes (slot 4)
    ItemType typeId;             // 32 bytes (slot 5)
    ItemStatus status;           // 32 bytes (slot 6)
} // Total: 192 bytes = 6 slots
```

**Requirements**:
- MUST pack structs to minimize storage slots
- MUST order fields by size (largest to smallest)
- SHOULD use smallest appropriate integer types
- MUST document storage layout for complex structs

#### Mapping Optimization
```solidity
// GOOD: Packed mapping values
mapping(uint256 => Token) private _tokens;  // Token struct is packed

// GOOD: Direct value mappings for simple state
mapping(address => bool) private _hasMinted;  // Simple boolean

// BAD: Unpacked mapping values
mapping(uint256 => TokenBad) private _tokensBad;  // Unpacked struct
```

### Computation Optimization

#### Safe Unchecked Arithmetic
```solidity
// GOOD: Unchecked when mathematically safe
function totalSupply() external view returns (uint256) {
    unchecked {
        return _nextTokenId - 1;  // _nextTokenId starts at 1
    }
}

// GOOD: Loop increment optimization
for (uint256 i = 0; i < items.length;) {
    // loop body
    unchecked {
        ++i;  // Pre-increment is cheaper than post-increment
    }
}

// BAD: Unnecessary checked arithmetic
function totalSupply() external view returns (uint256) {
    return _nextTokenId - 1;  // Solidity will check for underflow unnecessarily
}
```

**Requirements**:
- MUST use `unchecked` blocks for mathematically safe operations
- MUST use pre-increment (`++i`) instead of post-increment (`i++`)
- SHOULD combine multiple arithmetic operations in single unchecked block where safe
- MUST document why arithmetic is safe in comments

#### Loop Optimization
```solidity
// GOOD: Cache array length and use unchecked increments
function processItems(uint256[] calldata items) external {
    uint256 length = items.length;
    for (uint256 i = 0; i < length;) {
        // Process items[i]
        unchecked {
            ++i;
        }
    }
}

// BAD: Repeated array length access
function processItemsBad(uint256[] calldata items) external {
    for (uint256 i = 0; i < items.length; i++) {
        // Process items[i] 
    }
}
```

**Requirements**:
- MUST cache array lengths in variables
- MUST use unchecked increment in loops
- SHOULD minimize storage reads within loops
- MAY use assembly for high-performance loops when necessary

### Call Optimization

#### External Call Batching
```solidity
// GOOD: Batch related external calls
function batchUpdate(uint256[] calldata tokenIds, uint256[] calldata values) external {
    uint256 length = tokenIds.length;
    for (uint256 i = 0; i < length;) {
        _updateAttribute(tokenIds[i], values[i]);
        unchecked {
            ++i;
        }
    }
    emit BatchUpdateCompleted(tokenIds.length);
}

// BAD: Individual external calls
function updateMultiple(uint256[] calldata tokenIds, uint256[] calldata values) external {
    uint256 length = tokenIds.length;
    for (uint256 i = 0; i < length;) {
        updateAttribute(tokenIds[i], values[i]);  // External call in loop
        unchecked {
            ++i;
        }
    }
}
```

**Requirements**:
- SHOULD provide batch functions for repeated operations
- MUST minimize external calls in loops
- MAY use assembly for gas-critical operations
- SHOULD emit summary events for batch operations

### Gas Testing Requirements

```solidity
/// @notice Test gas usage for critical functions
function testGas_CreateItem() public {
    vm.deal(ALICE, 1 ether);

    uint256 gasBefore = gasleft();
    vm.prank(ALICE);
    exampleContract.create{value: CREATION_PRICE}();
    uint256 gasUsed = gasBefore - gasleft();

    // Assert gas usage is within acceptable bounds
    assertLt(gasUsed, 200_000, "Create gas usage too high");
    emit log_named_uint("Create gas used", gasUsed);
}
```

**Requirements**:
- MUST test gas usage for all critical functions
- MUST set maximum acceptable gas limits for functions
- SHOULD log gas usage in tests for monitoring
- MUST fail tests if gas usage exceeds limits

This comprehensive development standards document ensures consistent, secure, and efficient code across the entire smart contract protocol. All developers must familiarize themselves with these standards and apply them consistently in their contributions.