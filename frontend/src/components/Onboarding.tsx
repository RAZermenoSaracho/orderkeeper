function Onboarding() {
  return (
    <section className="onboarding-card" aria-labelledby="onboarding-title">
      <h2 id="onboarding-title">Automated limit orders on Sepolia</h2>
      <p>OrderKeeper is a Web3 app. To get started:</p>
      <ol>
        <li>Use MetaMask or another compatible Ethereum wallet in your browser.</li>
        <li>Create or import a wallet and switch it to Sepolia testnet.</li>
        <li>Fund it with Sepolia ETH for gas and Sell orders.</li>
        <li>Connect your wallet to create and view your orders.</li>
      </ol>
      <a className="onboarding-link" href="https://metamask.io/download/" target="_blank" rel="noopener noreferrer">
        Need a wallet? Get MetaMask
      </a>
    </section>
  )
}

export default Onboarding
