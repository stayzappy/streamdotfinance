# StreamDot Finance
**The Universal Native Asset Payroll Protocol for Polkadot Asset Hub.**

<img width="640" height="341" alt="6" src="https://github.com/user-attachments/assets/b4891d06-4785-4acf-91c0-fc767965d24e" />

[![Live dApp](https://img.shields.io/badge/Live_dApp-StreamDot-E6007A?style=for-the-badge)](https://streamdotfinance.web.app)
[![YouTube Demo](https://img.shields.io/badge/YouTube-Video_Demo-FF0000?style=for-the-badge&logo=youtube)](#) 

---

## Overview
StreamDot is a trustless, continuous payroll protocol built natively on the Polkadot Virtual Machine (PVM). 

Currently, Web3 payroll relies on manual, end-of-the-month batch transfers. This creates counterparty risk for contributors and administrative friction for DAOs. Furthermore, legacy EVM streaming protocols cannot handle Layer-0 gas tokens natively; they force users to wrap their assets (e.g., WETH, WDOT), adding unnecessary transaction fees and severe UX hurdles.

StreamDot solves this by enabling DAOs and employers to universally stream pure, unwrapped native DOT and stablecoins directly to contributors by the second, completely eliminating counterparty risk and token-wrapping friction.

## 📸 Platform Interface

<p align="center">
  <img src="https://github.com/user-attachments/assets/1c48114e-ab40-4b19-9faf-2c2f767fadd2" width="49%" alt="Employer Dashboard">
  <img src="https://github.com/user-attachments/assets/7684b571-517f-46fd-93c2-19e64d811b22" width="49%" alt="Create Stream View">
</p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/31dd04dd-45e6-4e11-9815-6911b2001338" width="49%" alt="Cryptographic Pay Stub">
  <img src="https://github.com/user-attachments/assets/a506374e-b405-41a8-bff6-8c181055e5d8" width="49%" alt="Live Digital Odometer">
</p>

## Under the Hood: PVM Architecture
By leveraging the unique architecture of the Polkadot Virtual Machine, StreamDot fundamentally re-engineers how token streaming works:

* **The Omni-Asset Router:** We utilize the PVM’s advanced precompiles to build an Omni-Asset Router. Employers can stream standard ERC-20 tokens (like USDC/USDT) *and* pure, unwrapped Native Gas (PAS/DOT) through the exact same smart contract.
* **Pull-over-Push Mechanics:** Employers lock the total capital upfront. The smart contract relies entirely on the PVM’s global block timestamp to mathematically unlock fractions of a cent every millisecond. The contract requires zero background execution gas, remaining completely dormant until an employee pulls their guaranteed earnings.
* **Zero-State History Indexer:** The frontend utilizes zero-gas `eth_call` loops against the PVM node to dynamically parse active, completed, and cancelled streams directly from the EVM struct mappings without relying on external centralized indexers.

## Key Features
* **Live Digital Odometer:** A high-frequency ticker visually renders tokens and their fiat equivalent unlocking in real-time, giving employees instant visual feedback on their earnings.
* **Cryptographic Pay Stubs:** Employers can generate secure, shareable deep-links that act as digital pay stubs. These links utilize strict wallet-address gatekeeping to ensure only the intended recipient can access the claim portal.
* **Context-Aware UI:** The interface dynamically adapts its taxonomy ("Funding" vs "Earning") based on whether the connected wallet belongs to the employer deploying capital or the employee receiving it.
* **Immutable Ledger:** Users can instantly view their entire chronological history of settled, active, and employer-cancelled streams directly from the chain.

## Deployed Contracts
* **Testnet (Paseo PVM):** [`0x9d939233A26ff54780F980513C1D4420B8C2C6de`](https://blockscout-testnet.polkadot.io/address/0x9d939233A26ff54780F980513C1D4420B8C2C6de)
* **Mainnet (Polkadot PVM):** *Migration scheduled pending final testnet audit.*

## Local Development

**Prerequisites:**
* Flutter SDK
* Node.js & Hardhat (for local contract interaction)

**Frontend Setup:**
```bash
# Clone the repository
git clone [https://github.com/YOUR_USERNAME/streamdot-finance.git](https://github.com/YOUR_USERNAME/streamdot-finance.git)
cd streamdot-finance

# Install dependencies
flutter pub get

# Run locally
flutter run -d chrome
