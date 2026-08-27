import { useAccount, useBalance, useConnect, useDisconnect } from 'wagmi'
import { formatUnits } from 'viem'

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

function App() {
  return (
    <>
      <header>
        <h1>OrderKeeper</h1>
        <ConnectButton />
      </header>
      <main>{/* Order creation and history land in a later task. */}</main>
    </>
  )
}

export default App
