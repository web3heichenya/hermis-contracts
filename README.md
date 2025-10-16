# Hermis Protocol
*Blockchain-based Decentralized Crowdsourcing Collaboration Platform*

## 🎯 Overview

Hermis Protocol decentralizes the crowdsourcing marketplace so task publishers, collaborators, and reviewers can coordinate without intermediaries. Smart contracts manage task lifecycles, escrow funds, and enforce programmable policies, while on-chain reputation and arbitration modules keep the ecosystem fair and transparent.

### Key Features

- **🤝 Decentralized Collaboration**: Direct interaction between publishers and contributors secured by smart contracts
- **🏆 Reputation-Driven Matching**: Dynamic scoring system influences eligibility, rewards, and review priority
- **🛡️ Policy Guards**: Composable guard modules enforce access, submission, and review rules per task
- **⚖️ Transparent Arbitration**: Programmable dispute workflows finalize payouts and penalties on-chain
- **💰 Token Incentives**: Treasury-backed payouts and configurable reward strategies align stakeholder interests
- **🪪 Soulbound Identity**: Hermis SBT anchors participant identity, making reputation and penalties non-transferable

## 🏗️ Architecture Overview

The Hermis smart contract suite is organized into modular layers for flexibility and upgradeability:

### Core Contracts

- **`TaskManager`** – Creates tasks, manages funding requirements, and tracks status transitions
- **`SubmissionManager`** – Records submissions, orchestrates reviewer assignments, and settles outcomes
- **`ReputationManager`** – Maintains contributor and reviewer scores that influence future participation

### Governance & Policy Modules

- **`AllowlistManager`** – Curates approved guards, strategies, and reward tokens for use across the protocol
- **Guards (`GlobalGuard`, `SubmissionGuard`, `ReviewGuard`)** – Enforce granular preconditions before task actions execute

### Strategy Layer & Extensions

- **Adoption Strategies** – Determine collaborator selection and slot allocation rules
- **Reward Strategies** – Split payouts between collaborators, reviewers, and the treasury based on task context
- **Upgradeable Hooks** – Additional modules can augment lifecycle events without redeploying core contracts

### Infrastructure & Identity

- **`Treasury`** – Escrows funds, routes rewards, and protects balances from improper withdrawal
- **`HermisSBT`** – Issues non-transferable identity tokens to track reputation and enforce penalties
- **`ArbitrationManager`** – Coordinates dispute resolution phases and enforces binding outcomes

## 🚀 Getting Started

### Prerequisites

- Node.js (v18+)
- Foundry
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/hermis-protocol.git
   cd hermis-protocol/contracts
   ```
2. **Install dependencies**
   ```bash
   make install
   # or
   forge install
   ```
3. **Configure environment**
   ```bash
   cp .env.example .env  # if available, otherwise edit .env manually
   # Populate RPC URLs, deployer keys, and explorer API tokens
   ```
4. **Build contracts**
   ```bash
   make build
   ```
5. **Run tests**
   ```bash
   make test
   ```

### Quick Development Setup

```bash
# Complete local toolchain setup
make dev-setup

# Generate gas report
make gas-report

# Deploy to a local Anvil fork (requires anvil running separately)
forge script script/DeployHermis.s.sol --fork-url http://127.0.0.1:8545 --broadcast
```

## 📋 Core Mechanics

### Task Lifecycle
1. **Publish** – Task owner defines scope, stakes funds in `Treasury`, and selects guards and strategies
2. **Adopt** – Approved collaborators accept tasks based on guard validation and reputation thresholds
3. **Submit** – Contributors deliver work through `SubmissionManager`; submissions are time-stamped and escrowed
4. **Review** – Reviewers or task owners evaluate deliverables, triggering reward strategies and reputation updates
5. **Arbitrate (optional)** – Disputed outcomes escalate to `ArbitrationManager` for binding resolution

### Roles & Permissions

- **Publishers**: Fund tasks, configure policies, and initiate reviews
- **Collaborators**: Submit work products and receive rewards based on performance
- **Reviewers**: Provide approvals, rejections, or escalation signals within defined time windows
- **Arbitrators**: Resolve disputes when consensus fails, applying penalties or releasing funds

### Reputation & Incentives

- Positive contributions increase collaborator and reviewer scores, unlocking premium tasks
- Failures or malicious activity result in score deductions and potential guard-level restrictions
- Reward strategies support split payouts, reviewer bonuses, and treasury fees for sustainability

### Arbitration Flow

1. Dispute triggered by publisher or collaborator
2. Evidence submitted to `ArbitrationManager`
3. Arbitrators (or automated policy) issue verdict
4. Treasury releases funds and updates reputation according to the ruling

## 🛠️ Development

### Project Structure

```
contracts/
├── src/
│   ├── core/                # Primary contracts: Task, Submission, Reputation, Treasury, etc.
│   ├── guards/              # Guard base class and concrete guard implementations
│   ├── strategies/          # Adoption and reward strategy contracts
│   ├── interfaces/          # Shared interfaces used across modules
│   └── libraries/           # Utility libraries and helpers
├── script/                  # Deployment and verification scripts
├── test/                    # Foundry test suites (unit, integration, security)
├── docs/                    # Supplemental documentation
└── Makefile                 # Developer command shortcuts
```

### Key Development Commands

```bash
make build             # Compile contracts
make test              # Run verbose test suite
make test-coverage     # Generate coverage report
make lint-all          # Run formatting, linting, and security checks
make lint-security     # Execute Slither analysis
make clean             # Remove build artifacts
```

### Testing Strategy

- **Unit Tests** – Validate individual guard, strategy, and core contract behaviors
- **Integration Tests** – Exercise end-to-end task publication, submission, and settlement flows
- **Security Tests** – Cover reentrancy, double-spend, and authorization edge cases
- **Economic Simulations** – Verify reward distribution and treasury accounting logic
- **Regression Suites** – Ensure bug fixes remain covered through scenario tests

Comprehensive Foundry suites currently include 296 tests with a 100% pass rate.

## 🔒 Security

### Security Measures

- **Reentrancy Protection**: Critical entry points guarded with OpenZeppelin `ReentrancyGuard`
- **Access Control**: Role-based permissions and guard checks enforce least-privilege operations
- **Treasury Safety**: Escrow logic prevents premature withdrawals and double payouts
- **Review Safeguards**: Time-bound windows and quorum rules avoid rushed or unilateral decisions

### Audits & Analysis

- Internal security reviews across the guard and strategy layers
- Automated analysis with Slither and Forge invariants
- Continuous test suite expansion with new attack scenarios

### Known Limitations

- Requires allowlist updates to onboard new guard/strategy modules
- Arbitration outcomes depend on configured arbitrator sets or governance participation
- Off-chain evidence submission must be managed by the front-end or auxiliary services

## 📊 Gas Optimization

- **Packed Structs**: Storage layouts minimize slot usage for task and submission records
- **Selective Events**: Emitted data focuses on critical workflow checkpoints to limit gas costs
- **Batch Operations**: Guard and strategy registries support batched updates for governance actions
- **Unchecked Math**: Applied in safe contexts to reduce opcode overhead

## 🌐 Deployment

### Supported Networks

- **Base Sepolia Testnet**: Full suite deployed for integration testing
- **Local Development**: Anvil/Hardhat forks for rapid iteration
- **Ethereum Mainnet**: Planned production deployment (in progress)

### Environment Variables

```bash
PRIVATE_KEY=              # Deployer private key
BASE_SEPOLIA_RPC_URL=     # Base Sepolia RPC endpoint
MAINNET_RPC_URL=          # Mainnet RPC endpoint (when applicable)
ETHERSCAN_API_KEY=        # Explorer API key for verification
```

### Deployment Process

1. Configure `.env` with RPC endpoints, deployer key, and explorer API token
2. Fund the deployer account on the target network
3. Deploy contracts
   ```bash
   forge script script/DeployHermis.s.sol \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast --verify
   ```
4. Verify deployments and store artifacts under `deployments/`
5. Register approved guards, strategies, and reward tokens via governance transactions
6. (Optional) Run `script/VerifyDeployment.s.sol` to cross-check configuration

#### Base Sepolia Contracts (Chain ID 84532)

| Module | Address | Explorer |
|--------|---------|----------|
| TaskManager | `0x5Fc6133a49Be7B8395e2A0978b6B06B1Ed72f424` | [View](https://sepolia.basescan.org/address/0x5Fc6133a49Be7B8395e2A0978b6B06B1Ed72f424) |
| SubmissionManager | `0xa770ffD8ce8f23D47b6E65E63280953Fd37dA3c2` | [View](https://sepolia.basescan.org/address/0xa770ffD8ce8f23D47b6E65E63280953Fd37dA3c2) |
| ReputationManager | `0x993966471695DfE32fD263D0C255D921FB9d02a6` | [View](https://sepolia.basescan.org/address/0x993966471695DfE32fD263D0C255D921FB9d02a6) |
| AllowlistManager | `0x3B3E3EE79BF8cE7fdd144D93f275E765aEb1BE48` | [View](https://sepolia.basescan.org/address/0x3B3E3EE79BF8cE7fdd144D93f275E765aEb1BE48) |
| ArbitrationManager | `0xDF2e26eE889Eb3b63BE42B36dD619fE306F70CB9` | [View](https://sepolia.basescan.org/address/0xDF2e26eE889Eb3b63BE42B36dD619fE306F70CB9) |
| Treasury | `0x1cc16662dAE018D4799689aBF15A974106EeE09b` | [View](https://sepolia.basescan.org/address/0x1cc16662dAE018D4799689aBF15A974106EeE09b) |
| HermisSBT | `0xD44d9D61C36f2FB0B0095dA91B9541BFEfD94749` | [View](https://sepolia.basescan.org/address/0xD44d9D61C36f2FB0B0095dA91B9541BFEfD94749) |
| GlobalGuard | `0x0150192A139d592cC50179291a6A40fD228EB4a5` | [View](https://sepolia.basescan.org/address/0x0150192A139d592cC50179291a6A40fD228EB4a5) |
| SubmissionGuard | `0x65DA79467f60cB4829183d50Bb4fA9A836DfcB07` | [View](https://sepolia.basescan.org/address/0x65DA79467f60cB4829183d50Bb4fA9A836DfcB07) |
| ReviewGuard | `0x3a0508bBf4ACD261Fe3FECb1267be0fbCCca6DbA` | [View](https://sepolia.basescan.org/address/0x3a0508bBf4ACD261Fe3FECb1267be0fbCCca6DbA) |

## 📈 Roadmap

### Phase 1 – Protocol Foundation (Completed)
- ✅ Core task, submission, and reputation contracts
- ✅ Allowlist and guard framework
- ✅ Reward strategy implementations
- ✅ Full test suite with security scenarios
- ✅ Base Sepolia deployment and verification

### Phase 2 – Ecosystem Expansion (In Progress)
- 📋 DAO governance integration for guard approvals
- 📋 Multi-token reward support and streaming payouts
- 📋 Reviewer staking and slashing mechanisms
- 📋 Front-end enhancements and analytics dashboards

### Phase 3 – Production Launch (Planned)
- 📋 Mainnet deployment and liquidity bootstrapping
- 📋 Third-party arbitration marketplace
- 📋 Advanced analytics and reputation visualization

## 🤝 Contributing

We welcome community contributions! Please review the [CONTRIBUTING.md](CONTRIBUTING.md) guide for:

- Coding standards and formatting
- Testing requirements (`make ci-test`)
- Pull request workflow and review expectations
- Issue templates and triage process

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Implement changes with accompanying tests
4. Run `make ci-test`
5. Submit a pull request describing motivation, changes, and test results

## 📄 License

Hermis Protocol is licensed under the MIT License – see [LICENSE](LICENSE) for details.

## 🔗 Links

<div align="center">

[![Visit Hermis](https://img.shields.io/badge/🌐%20Visit-Hermis-blue?style=for-the-badge&logo=vercel&logoColor=white)](https://hermis-next.vercel.app/) [![Follow on Twitter](https://img.shields.io/badge/🐦%20Follow-@web3heichen-blue?style=for-the-badge&logo=twitter&logoColor=white)](https://x.com/web3heichen)

</div>

## ⚠️ Disclaimer

Hermis Protocol is experimental software. Interact at your own risk. Audit results, test coverage, and deployment artifacts are provided for transparency but do not eliminate risk. Always review contracts and understand the implications before staking funds.

---

*Built with ❤️ by the Hermis Protocol Team*
