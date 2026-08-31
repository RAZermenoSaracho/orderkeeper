function Onboarding() {
  return (
    <section className="onboarding-card" aria-labelledby="onboarding-title">
      <h2 id="onboarding-title">Automated limit orders on Sepolia</h2>
      <p>OrderKeeper is a Web3 app. To get started:</p>
      <ol>
        <li>Use MetaMask or another compatible Ethereum wallet in your browser.</li>
        <li>Create or import a wallet and switch it to Sepolia testnet.</li>
        <li>Fund it with Sepolia ETH for gas and Sell orders.</li>
        <li>
          Buy orders require mock USDC (mUSDC). To mint 5 mUSDC, enter your wallet as <code>to</code> and{' '}
          <code>5000000</code> as <code>amount</code>.
        </li>
        <li>Connect your wallet to create and view your orders.</li>
      </ol>
      <p>
        <a
          className="onboarding-link"
          href="https://sepolia.etherscan.io/address/0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929#writeContract"
          target="_blank"
          rel="noopener noreferrer"
        >
          Get test mUSDC
        </a>
      </p>
      <a className="onboarding-link" href="https://metamask.io/download/" target="_blank" rel="noopener noreferrer">
        Need a wallet? Get MetaMask
      </a>
      <p>
        Sepolia contracts:{' '}
        <a
          className="onboarding-link"
          href="https://sepolia.etherscan.io/address/0x907dC6392df5973aD82816C05E2e15F821054503#code"
          target="_blank"
          rel="noopener noreferrer"
        >
          OrderKeeper ↗
        </a>{' '}
        ·{' '}
        <a
          className="onboarding-link"
          href="https://sepolia.etherscan.io/address/0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929#code"
          target="_blank"
          rel="noopener noreferrer"
        >
          Mock USDC ↗
        </a>
      </p>
    </section>
  )
}

export default Onboarding
