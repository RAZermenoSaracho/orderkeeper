import { useEffect, useRef } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { BaseError, formatUnits } from 'viem'
import { orderKeeperAbi } from './abi.ts'
import { indexerUrl, orderKeeperAddress } from './config.ts'

// Matches order-indexer's serializeOrder() (order-indexer/src/routes/orders.ts).
interface IndexedOrder {
  orderId: number
  owner: string
  asset: string
  condition: 'GreaterOrEqual' | 'LessOrEqual'
  targetPrice: string
  amount: string
  maxSlippageBps: number
  expiry: string
  status: 'Pending' | 'Executed' | 'Cancelled'
  createdAtTx: string
  executionPrice: string | null
  keeperFee: string | null
  amountOut: string | null
}

interface OrdersResponse {
  data: IndexedOrder[]
  meta: { count: number }
}

const POLL_INTERVAL_MS = 10_000
const CONDITION_LABEL: Record<IndexedOrder['condition'], string> = {
  GreaterOrEqual: '≥',
  LessOrEqual: '≤',
}

// GET /orders has no owner filter yet (see .claude/rules/api-conventions.md
// — only ?status= is implemented), so this fetches everything and filters
// to the connected wallet client-side.
async function fetchOrders(): Promise<IndexedOrder[]> {
  const response = await fetch(`${indexerUrl}/orders`, { signal: AbortSignal.timeout(5_000) })
  if (!response.ok) {
    throw new Error(`order-indexer returned ${response.status}`)
  }
  const body = (await response.json()) as OrdersResponse
  return body.data
}

function CancelButton({ orderId, onCancelled }: { orderId: number; onCancelled: () => void }) {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  // Guards against re-firing on every parent re-render — onCancelled isn't
  // a stable reference, but this must only notify the parent once per
  // successful cancellation.
  const notified = useRef(false)
  useEffect(() => {
    if (isSuccess && !notified.current) {
      notified.current = true
      onCancelled()
    }
  }, [isSuccess, onCancelled])

  const isSubmitting = isPending || isConfirming

  return (
    <div className="cancel-cell">
      <button
        type="button"
        disabled={isSubmitting}
        onClick={() =>
          writeContract({
            address: orderKeeperAddress,
            abi: orderKeeperAbi,
            functionName: 'cancelOrder',
            args: [BigInt(orderId)],
          })
        }
      >
        {isPending ? 'Confirm in wallet...' : isConfirming ? 'Cancelling...' : 'Cancel'}
      </button>
      {error && <span className="form-error">{error instanceof BaseError ? error.shortMessage : error.message}</span>}
    </div>
  )
}

function OrderList() {
  const { address } = useAccount()
  const {
    data: orders,
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['orders'],
    queryFn: fetchOrders,
    // Pauses automatically while the tab isn't visible/focused (react-query
    // default: refetchIntervalInBackground is false).
    refetchInterval: POLL_INTERVAL_MS,
  })

  const myOrders = (orders ?? []).filter(
    (order) => address !== undefined && order.owner.toLowerCase() === address.toLowerCase(),
  )

  return (
    <section className="order-list">
      <div className="order-list-header">
        <h2>Your Orders</h2>
        <button type="button" onClick={() => refetch()} disabled={isFetching}>
          {isFetching ? 'Refreshing...' : 'Refresh'}
        </button>
      </div>

      {isLoading && <p>Loading orders...</p>}
      {error && <p className="form-error">Could not load orders: {error.message}</p>}
      {!isLoading && !error && myOrders.length === 0 && <p>No orders yet.</p>}

      {myOrders.length > 0 && (
        <ul className="order-items">
          {myOrders.map((order) => (
            <li key={order.orderId} className="order-item">
              <div className="order-item-row">
                <span>#{order.orderId}</span>
                <span>{order.status}</span>
              </div>
              <div className="order-item-row">
                <span>
                  Asset: WETH ({order.asset.slice(0, 6)}...{order.asset.slice(-4)})
                </span>
              </div>
              <div className="order-item-row">
                <span>
                  Condition: price {CONDITION_LABEL[order.condition]} ${formatUnits(BigInt(order.targetPrice), 18)}
                </span>
              </div>
              <div className="order-item-row">
                <span>Amount: {formatUnits(BigInt(order.amount), 18)} ETH</span>
              </div>
              {order.status === 'Executed' && order.executionPrice && order.keeperFee && order.amountOut && (
                <div className="order-item-row">
                  <span>
                    Executed at ${formatUnits(BigInt(order.executionPrice), 18)} — fee{' '}
                    {formatUnits(BigInt(order.keeperFee), 18)} ETH — received{' '}
                    {formatUnits(BigInt(order.amountOut), 6)} mUSDC
                  </span>
                </div>
              )}
              {order.status === 'Pending' && <CancelButton orderId={order.orderId} onCancelled={() => refetch()} />}
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

export default OrderList
