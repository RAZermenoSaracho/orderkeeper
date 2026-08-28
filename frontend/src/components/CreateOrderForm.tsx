import { useEffect, useState } from 'react'
import { useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { BaseError, formatUnits, parseEther, parseUnits, type Address } from 'viem'
import { orderKeeperAbi } from '../abi.ts'
import { orderKeeperAddress, SUPPORTED_ASSETS } from '../config.ts'

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

function LivePrice({ asset }: { asset: Address }) {
  const {
    data: price,
    error,
    dataUpdatedAt,
  } = useReadContract({
    address: orderKeeperAddress,
    abi: orderKeeperAbi,
    functionName: 'getAssetPrice',
    args: [asset],
    query: {
      // Reads exactly what executeOrder() would evaluate (staleness
      // checks and decimal normalization included) via the contract's
      // own getAssetPrice(), rather than reading Chainlink directly, so
      // this can never show a price the contract itself would disagree
      // with. See ROADMAP.md's Live Price Display milestone.
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
  const [assetIndex, setAssetIndex] = useState(0)
  const selectedAsset = SUPPORTED_ASSETS[assetIndex]!
  const [condition, setCondition] = useState<0 | 1>(0)
  const [targetPrice, setTargetPrice] = useState('')
  const [ethAmount, setEthAmount] = useState('')
  const [maxSlippageBps, setMaxSlippageBps] = useState(DEFAULT_MAX_SLIPPAGE_BPS)
  const [expiryHours, setExpiryHours] = useState(DEFAULT_EXPIRY_HOURS)
  const [formError, setFormError] = useState<string | null>(null)

  const { writeContract, data: hash, isPending, error: writeError, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash })

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    setFormError(null)

    let targetPriceWei: bigint
    let ethAmountWei: bigint
    let maxSlippageBpsNum: bigint
    let expiryTimestamp: bigint
    try {
      targetPriceWei = parseUnits(targetPrice, PRICE_DECIMALS)
      ethAmountWei = parseEther(ethAmount)
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

    if (ethAmountWei === 0n) {
      setFormError('ETH amount must be greater than 0')
      return
    }

    writeContract({
      address: orderKeeperAddress,
      abi: orderKeeperAbi,
      functionName: 'createOrder',
      args: [selectedAsset.address, condition, targetPriceWei, maxSlippageBpsNum, expiryTimestamp],
      value: ethAmountWei,
    })
  }

  function handleReset() {
    setTargetPrice('')
    setEthAmount('')
    setMaxSlippageBps(DEFAULT_MAX_SLIPPAGE_BPS)
    setExpiryHours(DEFAULT_EXPIRY_HOURS)
    setFormError(null)
    reset()
  }

  const isSubmitting = isPending || isConfirming

  return (
    <form className="create-order-form" onSubmit={handleSubmit}>
      <h2>Create Order</h2>

      <label className="form-row">
        <span className="form-label">Asset</span>
        <select
          value={assetIndex}
          onChange={(event) => setAssetIndex(Number(event.target.value))}
          disabled={isSubmitting}
        >
          {SUPPORTED_ASSETS.map((asset, index) => (
            <option key={asset.address} value={index}>
              {asset.label} ({asset.address.slice(0, 6)}...{asset.address.slice(-4)})
            </option>
          ))}
        </select>
      </label>

      <div className="form-row">
        <span className="form-label">Live price</span>
        <LivePrice asset={selectedAsset.address} />
      </div>

      <label className="form-row">
        <span className="form-label">Condition</span>
        <select
          value={condition}
          onChange={(event) => setCondition(Number(event.target.value) as 0 | 1)}
          disabled={isSubmitting}
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
          disabled={isSubmitting}
          required
        />
      </label>

      <label className="form-row">
        <span className="form-label">ETH to deposit</span>
        <input
          type="number"
          step="any"
          min="0"
          placeholder="e.g. 0.01"
          value={ethAmount}
          onChange={(event) => setEthAmount(event.target.value)}
          disabled={isSubmitting}
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
          disabled={isSubmitting}
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
          disabled={isSubmitting}
          required
        />
      </label>

      <button type="submit" disabled={isSubmitting}>
        {isPending ? 'Confirm in wallet...' : isConfirming ? 'Creating order...' : 'Create Order'}
      </button>

      {formError && <p className="form-error">{formError}</p>}

      {writeError && (
        <p className="form-error">
          {writeError instanceof BaseError ? writeError.shortMessage : writeError.message}
        </p>
      )}

      {isConfirmed && hash && (
        <p className="form-success">
          Order created —{' '}
          <a href={`https://sepolia.etherscan.io/tx/${hash}`} target="_blank" rel="noreferrer">
            view on Etherscan
          </a>
          <button type="button" onClick={handleReset}>
            Create another
          </button>
        </p>
      )}
    </form>
  )
}

export default CreateOrderForm
