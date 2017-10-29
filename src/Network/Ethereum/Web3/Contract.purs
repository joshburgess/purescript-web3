module Network.Ethereum.Web3.Contract where

import Prelude

import Control.Monad.Aff (Canceler(..))
import Control.Monad.Eff.Exception (error)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Reader (ReaderT)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq (genericEq)
import Data.Generic.Rep.Show (genericShow)
import Data.Lens ((.~))
import Data.Maybe (Maybe(..))
import Data.Monoid (mempty)
import Network.Ethereum.Web3.Api (eth_call, eth_call_async, eth_sendTransaction, eth_sendTransaction_async)
import Network.Ethereum.Web3.Solidity.AbiEncoding (class ABIEncoding, toDataBuilder, fromData)
import Network.Ethereum.Web3.Types (Address, BigNumber, CallMode, Change, Filter, HexString, Web3M, Web3MA, _data, _from, _gas, _to, _value, defaultTransactionOptions, hexadecimal, parseBigNumber)

--------------------------------------------------------------------------------
-- | Events
--------------------------------------------------------------------------------

data EventAction = ContinueEvent
                 -- ^ Continue to listen events
                 | TerminateEvent
                 -- ^ Terminate event listener

derive instance genericEventAction :: Generic EventAction _

instance showEventAction :: Show EventAction where
  show = genericShow

instance eqEventAction :: Eq EventAction where
  eq = genericEq

class ABIEncoding a <= Event a where
    -- | Event filter structure used by low-level subscription methods
    eventFilter :: a -> Address -> Filter

    -- | Start an event listener for given contract 'Address' and callback
    event :: forall e .
             Address
          -- ^ Contract address
          -> (a -> ReaderT Change (Web3MA e) EventAction)
          -- ^ 'Event' handler
          -> Web3MA e (Canceler e)
          -- ^ 'Web3' wrapped event handler spawn ident

_event :: forall e a.
          Event a
       => Address
       -> (a -> ReaderT Change (Web3MA e) EventAction)
       -> Web3MA e (Canceler e)
_event a f = pure mempty
--    fid <- let ftyp = snd $ let x = undefined :: Event a => 
--                            in  (f x, x)
--           in  eth_newFilter (eventFilter ftyp a)
--
--    forkWeb3 $
--        let loop = do liftIO (threadDelay 1000000)
--                      changes <- eth_getFilterChanges fid
--                      acts <- forM (mapMaybe pairChange changes) $ \(changeEvent, changeWithMeta) ->
--                        runReaderT (f changeEvent) changeWithMeta
--                      when (TerminateEvent `notElem` acts) loop
--        in do loop
--              eth_uninstallFilter fid
--              return ()
--  where
--    prepareTopics = fmap (T.drop 2) . drop 1
--    pairChange changeWithMeta = do
--      changeEvent <- fromData $
--        T.append (T.concat (prepareTopics $ changeTopics changeWithMeta))
--                 (T.drop 2 $ changeData changeWithMeta)
--      return (changeEvent, changeWithMeta)

--------------------------------------------------------------------------------
-- | Methods
--------------------------------------------------------------------------------

class ABIEncoding a <= Method a where
    -- | Send a transaction for given contract 'Address', value and input data
    sendTx :: forall e .
              Maybe Address
           -- ^ Contract address
           -> Address
           -- ^ from address
           -> BigNumber
           -- ^ paymentValue
           -> a
           -- ^ Method data
           -> Web3M e HexString
           -- ^ 'Web3' wrapped tx hash

    -- | Constant call given contract 'Address' in mode and given input data
    call :: forall e b .
            ABIEncoding b
         => Address
         -- ^ Contract address
         -> Maybe Address
         -- from address
         -> CallMode
         -- ^ State mode for constant call (latest or pending)
         -> a
         -- ^ Method data
         -> Web3M e b
         -- ^ 'Web3' wrapped result

instance methodAbiEncoding :: ABIEncoding a => Method a where
  sendTx = _sendTransaction
  call = _call

_sendTransaction :: forall a e .
                    ABIEncoding a
                 => Maybe Address
                 -> Address
                 -> BigNumber
                 -> a
                 -> Web3M e HexString
_sendTransaction mto f val dat =
    eth_sendTransaction (txdata $ toDataBuilder dat)
  where
    defaultGas = parseBigNumber hexadecimal "0x2dc2dc"
    txdata d =
      defaultTransactionOptions # _to .~ mto
                                # _from .~ Just f
                                # _data .~ Just d
                                # _value .~ Just val
                                # _gas .~ defaultGas

_call :: forall a b e .
         ABIEncoding a
      => ABIEncoding b
      => Address
      -> Maybe Address
      -> CallMode
      -> a
      -> Web3M e b
_call t mf cm dat = do
    res <- eth_call (txdata <<< toDataBuilder $ dat) cm
    case fromData res of
        Nothing -> throwError <<< error $ "Unable to parse result"
        Just x -> pure x
  where
    txdata d  =
      defaultTransactionOptions # _to .~ Just t
                                # _from .~ mf
                                # _data .~ Just d


--------------------------------------------------------------------------------
-- * Asynchronous Methods
--------------------------------------------------------------------------------
class AsyncMethod a where
    -- | Send a transaction for given contract 'Address', value and input data
    sendTxAsync :: forall e .
              Maybe Address
           -- ^ Contract address
           -> Address
           -- ^ from address
           -> BigNumber
           -- ^ paymentValue
           -> a
           -- ^ Method data
           -> Web3MA e HexString
           -- ^ 'Web3' wrapped tx hash

    -- | Constant call given contract 'Address' in mode and given input data
    callAsync :: forall b e .
            ABIEncoding b
         => Address
         -- ^ Contract address
         -> Maybe Address
         -- from address
         -> CallMode
         -- ^ State mode for constant call (latest or pending)
         -> a
         -- ^ Method data
         -> Web3MA e b
         -- ^ 'Web3' wrapped result

instance methodAsyncAbiEncoding :: ABIEncoding a => AsyncMethod a where
  sendTxAsync = _sendTransactionAsync
  callAsync = _callAsync

_sendTransactionAsync :: forall a e .
                    ABIEncoding a
                 => Maybe Address
                 -> Address
                 -> BigNumber
                 -> a
                 -> Web3MA e HexString
_sendTransactionAsync mto f val dat =
    eth_sendTransaction_async (txdata $ toDataBuilder dat)
  where
    defaultGas = parseBigNumber hexadecimal "0x2dc2dc"
    txdata d =
      defaultTransactionOptions # _to .~ mto
                                # _from .~ Just f
                                # _data .~ Just d
                                # _value .~ Just val
                                # _gas .~ defaultGas

_callAsync :: forall a b e .
         ABIEncoding a
      => ABIEncoding b
      => Address
      -> Maybe Address
      -> CallMode
      -> a
      -> Web3MA e b
_callAsync t mf cm dat = do
    res <- eth_call_async (txdata <<< toDataBuilder $ dat) cm
    case fromData res of
        Nothing -> throwError <<< error $ "Unable to parse result"
        Just x -> pure x
  where
    txdata d  =
      defaultTransactionOptions # _to .~ Just t
                                # _from .~ mf
                                # _data .~ Just d
