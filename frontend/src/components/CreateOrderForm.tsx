import { useEffect, useState } from 'react'
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { BaseError, formatUnits, parseUnits } from 'viem'
import { erc20Abi, orderKeeperAbi } from '../abi.ts'
import { orderKeeperAddress, quoteToken, wethAddress } from '../config.ts'

// Mirrors OrderKeeper.OrderSide's declaration order.
const SIDE_SELL = 0
const SIDE_BUY = 1
type OrderSide = typeof SIDE_SELL | typeof SIDE_BUY

const CONDITIONS = [
  { value: 0, label: 'Greater or equal (≥)' },
  { value: 1, label: 'Less or equal (≤)' },
] as const

const PRICE_DECIMALS = 18
const DEFAULT_MAX_SLIPPAGE_BPS = '100'
const DEFAULT_EXPIRY_HOURS = '24'
const PRICE_POLL_INTERVAL_MS = 15_000

// Ticks once a second so the "Xs ago" label stays live between polls,
// without re-fetching anything itself.
function useSecondsAgo(since: number | undefined): number | null {
  const [, tick] = useState(0)

  useEffect(() => {
    if (!since) return
    const interval = setInterval(() => tick((n) => n + 1), 1_000)
    return () => clearInterval(interval)
  }, [since])

  if (!since) return null
  return Math.max(0, Math.floor((Date.now() - since) / 1_000))
}

function LivePrice() {
  const {
    data: price,
    error,
    dataUpdatedAt,
  } = useReadContract({
    address: orderKeeperAddress,
    abi: orderKeeperAbi,
    functionName: 'getAssetPrice',
    args: [wethAddress],
    query: {
      // Reads exactly what executeOrder() would evaluate (staleness
      // checks and decimal normalization included) via the contract's
      // own getAssetPrice(), rather than reading Chainlink directly, so
      // this can never show a price the contract itself would disagree
      // with. Both order sides gate on this same ETH price.
      refetchInterval: PRICE_POLL_INTERVAL_MS,
    },
  })
  const secondsAgo = useSecondsAgo(dataUpdatedAt || undefined)

  if (error) {
    return <span className="form-static">Price unavailable</span>
  }

  return (
    <span className="form-static">
      {price !== undefined ? `$${Number(formatUnits(price, PRICE_DECIMALS)).toFixed(2)}` : 'Loading...'}
      {secondsAgo !== null && <span className="price-updated"> · updated {secondsAgo}s ago</span>}
    </span>
  )
}

function CreateOrderForm() {
  const { address } = useAccount()
  const [side, setSide] = useState<OrderSide>(SIDE_SELL)
  // Sell defaults to "sell when ETH rises", Buy to "buy when ETH falls" —
  // the conditions each side is actually useful with.
  const [condition, setCondition] = useState<0 | 1>(0)
  const [targetPrice, setTargetPrice] = useState('')
  const [amountInput, setAmountInput] = useState('')
  const [maxSlippageBps, setMaxSlippageBps] = useState(DEFAULT_MAX_SLIPPAGE_BPS)
  const [expiryHours, setExpiryHours] = useState(DEFAULT_EXPIRY_HOURS)
  const [formError, setFormError] = useState<string | null>(null)

  const isBuy = side === SIDE_BUY
  const depositLabel = isBuy ? `${quoteToken.label} to deposit` : 'ETH to deposit'
  const depositDecimals = isBuy ? quoteToken.decimals : 18

  // Parsed here rather than only at submit time so the approve step can
  // compare it against the current allowance.
  let parsedAmount: bigint | null = null
  try {
    parsedAmount = amountInput ? parseUnits(amountInput, depositDecimals) : null
  } catch {
    parsedAmount = null
  }

  // --- Buy-side approve flow ---------------------------------------------
  // A Buy order's deposit is pulled with transferFrom, so the user must
  // approve OrderKeeper first. That makes Buy a two-transaction flow
  // (approve, then create) where Sell stays one.
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: quoteToken.address,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address ? [address, orderKeeperAddress] : undefined,
    query: { enabled: isBuy && address !== undefined },
  })

  const needsApproval =
    isBuy && parsedAmount !== null && parsedAmount > 0n && (allowance === undefined || allowance < parsedAmount)

  const {
    writeContract: writeApprove,
    data: approveHash,
    isPending: isApprovePending,
    error: approveError,
  } = useWriteContract()
  const { isLoading: isApproveConfirming, isSuccess: isApproved } = useWaitForTransactionReceipt({ hash: approveHash })

  // Once the approval confirms, re-read the allowance so needsApproval
  // flips and the create step unlocks without a manual refresh.
  useEffect(() => {
    if (isApproved) void refetchAllowance()
  }, [isApproved, refetchAllowance])

  const { writeContract, data: hash, isPending, error: writeError } = useWriteContract()
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash })

  function handleApprove() {
    if (parsedAmount === null || parsedAmount === 0n) {
      setFormError('Enter a deposit amount before approving')
      return
    }
    setFormError(null)
    writeApprove({
      address: quoteToken.address,
      abi: erc20Abi,
      functionName: 'approve',
      args: [orderKeeperAddress, parsedAmount],
    })
  }

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    setFormError(null)

    let targetPriceWei: bigint
    let maxSlippageBpsNum: bigint
    let expiryTimestamp: bigint
    try {
      targetPriceWei = parseUnits(targetPrice, PRICE_DECIMALS)
      maxSlippageBpsNum = BigInt(maxSlippageBps)
      const hours = Number(expiryHours)
      if (!Number.isFinite(hours) || hours <= 0) {
        throw new Error('Expiry must be a positive number of hours')
      }
      expiryTimestamp = BigInt(Math.floor(Date.now() / 1000) + Math.floor(hours * 3600))
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Invalid input')
      return
    }

    if (parsedAmount === null || parsedAmount === 0n) {
      setFormError('Deposit amount must be greater than 0')
      return
    }

    writeContract({
      address: orderKeeperAddress,
      abi: orderKeeperAbi,
      functionName: 'createOrder',
      args: [side, condition, targetPriceWei, parsedAmount, maxSlippageBpsNum, expiryTimestamp],
      // Sell funds itself from msg.value; Buy's deposit comes from the
      // approved quoteToken pull, and the contract rejects stray ETH on it.
      value: isBuy ? 0n : parsedAmount,
    })
  }

  function handleSideChange(nextSide: OrderSide) {
    setSide(nextSide)
    // Reset the amount: it's denominated differently per side, so carrying
    // "0.01" from an ETH deposit into a quoteToken deposit would silently
    // mean something completely different.
    setAmountInput('')
    setCondition(nextSide === SIDE_BUY ? 1 : 0)
    setFormError(null)
  }

  const isSubmitting = isPending || isConfirming
  const isApproving = isApprovePending || isApproveConfirming
  const busy = isSubmitting || isApproving

  return (
    <form className="create-order-form" onSubmit={handleSubmit}>
      <h2>Create Order</h2>

      <label className="form-row">
        <span className="form-label">Side</span>
        <select
          value={side}
          onChange={(event) => handleSideChange(Number(event.target.value) as OrderSide)}
          disabled={busy}
        >
          <option value={SIDE_SELL}>Sell ETH &rarr; {quoteToken.label}</option>
          <option value={SIDE_BUY}>Buy ETH &larr; {quoteToken.label}</option>
        </select>
      </label>

      <div className="form-row">
        <span className="form-label">Live ETH price</span>
        <LivePrice />
      </div>

      <label className="form-row">
        <span className="form-label">Condition (on ETH price)</span>
        <select
          value={condition}
          onChange={(event) => setCondition(Number(event.target.value) as 0 | 1)}
          disabled={busy}
        >
          {CONDITIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      <label className="form-row">
        <span className="form-label">Target price (USD)</span>
        <input
          type="number"
          step="any"
          min="0"
          placeholder="e.g. 4000"
          value={targetPrice}
          onChange={(event) => setTargetPrice(event.target.value)}
          disabled={busy}
          required
        />
      </label>

      <label className="form-row">
        <span className="form-label">{depositLabel}</span>
        <input
          type="number"
          step="any"
          min="0"
          placeholder={isBuy ? 'e.g. 25' : 'e.g. 0.01'}
          value={amountInput}
          onChange={(event) => setAmountInput(event.target.value)}
          disabled={busy}
          required
        />
      </label>

      <label className="form-row">
        <span className="form-label">Max slippage (bps)</span>
        <input
          type="number"
          step="1"
          min="0"
          max="10000"
          value={maxSlippageBps}
          onChange={(event) => setMaxSlippageBps(event.target.value)}
          disabled={busy}
          required
        />
      </label>

      <label className="form-row">
        <span className="form-label">Expiry (hours from now)</span>
        <input
          type="number"
          step="any"
          min="0"
          value={expiryHours}
          onChange={(event) => setExpiryHours(event.target.value)}
          disabled={busy}
          required
        />
      </label>

      {needsApproval ? (
        <>
          <button type="button" onClick={handleApprove} disabled={busy}>
            {isApprovePending
              ? 'Confirm approval in wallet...'
              : isApproveConfirming
                ? 'Approving...'
                : `Approve ${quoteToken.label}`}
          </button>
          <p className="form-hint">
            Buy orders deposit {quoteToken.label}, so OrderKeeper needs your approval to transfer it before the order
            can be created.
          </p>
        </>
      ) : (
        <button type="submit" disabled={busy}>
          {isPending ? 'Confirm in wallet...' : isConfirming ? 'Creating order...' : 'Create Order'}
        </button>
      )}

      {formError && <p className="form-error">{formError}</p>}

      {approveError && (
        <p className="form-error">
          {approveError instanceof BaseError ? approveError.shortMessage : approveError.message}
        </p>
      )}

      {writeError && (
        <p className="form-error">{writeError instanceof BaseError ? writeError.shortMessage : writeError.message}</p>
      )}

      {isConfirmed && hash && (
        <p className="form-success">
          Order created —{' '}
          <a href={`https://sepolia.etherscan.io/tx/${hash}`} target="_blank" rel="noreferrer">
            view on Etherscan
          </a>
        </p>
      )}
    </form>
  )
}

export default CreateOrderForm
