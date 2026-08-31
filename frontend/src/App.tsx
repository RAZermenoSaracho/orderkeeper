import { useAccount, useBalance, useConnect, useDisconnect } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { formatUnits } from 'viem'
import CreateOrderForm from './components/CreateOrderForm.tsx'
import OrderList from './components/OrderList.tsx'

function ConnectButton() {
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const { data: balance } = useBalance({ address })

  if (isConnected && address) {
    return (
      <div className="wallet-info">
        <span className="wallet-balance">
          {balance ? `${formatUnits(balance.value, balance.decimals).slice(0, 6)} ${balance.symbol}` : '...'}
        </span>
        <span className="wallet-address">
          {address.slice(0, 6)}...{address.slice(-4)}
        </span>
        <button type="button" onClick={() => disconnect()}>
          Disconnect
        </button>
      </div>
    )
  }

  const injectedConnector = connectors.find((connector) => connector.type === 'injected')

  return (
    <button
      type="button"
      disabled={!injectedConnector || isPending}
      onClick={() => injectedConnector && connect({ connector: injectedConnector })}
    >
      {isPending ? 'Connecting...' : 'Connect Wallet'}
    </button>
  )
}

function OnboardingCard() {
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

function App() {
  const { isConnected, chainId } = useAccount()
  const isWrongNetwork = isConnected && chainId !== undefined && chainId !== sepolia.id

  return (
    <>
      <header>
        <h1>OrderKeeper</h1>
        <ConnectButton />
      </header>
      <main>
        {!isConnected && <OnboardingCard />}
        {isConnected && (
          <>
            {isWrongNetwork && (
              <p className="network-warning" role="alert">
                Wrong network. Switch your wallet to Sepolia testnet before creating an order.
              </p>
            )}
            <CreateOrderForm />
            <OrderList />
          </>
        )}
      </main>
    </>
  )
}

export default App
