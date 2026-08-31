import { formatUnits } from 'viem'
import { useAccount, useBalance, useConnect, useDisconnect } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import CreateOrderForm from '../components/CreateOrderForm.tsx'
import Onboarding from '../components/Onboarding.tsx'
import OrderList from '../components/OrderList.tsx'

function WalletControl({ address }: { address?: `0x${string}` }) {
  const { connect, connectors, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const { data: balance } = useBalance({ address })

  if (address) {
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

function Layout() {
  const { address, isConnected, chainId } = useAccount()
  const isWrongNetwork = isConnected && chainId !== undefined && chainId !== sepolia.id

  return (
    <>
      <header>
        <h1>OrderKeeper</h1>
        <WalletControl address={isConnected ? address : undefined} />
      </header>
      <main>
        {!isConnected ? (
          <Onboarding />
        ) : (
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

export default Layout
