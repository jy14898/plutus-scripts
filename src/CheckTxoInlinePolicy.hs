{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module CheckTxoInlinePolicy
  ( printRedeemerDatumHash,
    printRedeemerDatum,
    serialisedScript,
    scriptSBS,
    script,
    writeSerialisedScript,
    --  , runTrace
  )
where

import           Cardano.Api                     (writeFileTextEnvelope)
import           Cardano.Api.Shelley             (PlutusScript (..),
                                                  PlutusScriptV1,
                                                  ScriptDataJsonSchema (ScriptDataJsonDetailedSchema),
                                                  fromPlutusData,
                                                  scriptDataToJson,
                                                  toPlutusData)
import           Codec.Serialise
import           Data.Aeson                      as A
import qualified Data.ByteString.Lazy            as LBS
import qualified Data.ByteString.Short           as SBS
import           Data.Functor                    (void)
import           Ledger
import           Ledger.Ada                      as Ada
import           Ledger.Constraints              as Constraints
import qualified Ledger.Typed.Scripts            as Scripts
import           Ledger.Typed.Scripts.Validators
import           Ledger.Value                    as Value
import           Plutus.Contract                 as Contract
import           Plutus.Trace.Emulator           as Emulator
import qualified Plutus.V1.Ledger.Api            as Plutus.Api
import qualified Plutus.V1.Ledger.Scripts        as Plutus
import qualified PlutusTx
import qualified PlutusTx.Builtins               as BI
import           PlutusTx.Prelude                as P hiding (Semigroup (..),
                                                       unless, (.))
import           Prelude                         (IO, Semigroup (..), Show (..),
                                                  String, print, putStrLn, (.))
import           Wallet.Emulator.Wallet

{-
   Define redeemer type to handle expected inline datum or datum hash at a txo
-}

data ExpInline
    = ExpInlineDatum
        { txOutRef :: TxOutRef,
        expDatum   :: Datum
        }
    | ExpInlineDatumHash
        { txOutRef   :: TxOutRef,
        expDatumHash :: Maybe DatumHash
        }
    deriving (Show)

PlutusTx.unstableMakeIsData ''ExpInline

{-
   Define datum to use
-}

data SomeData = SomeData {name :: BuiltinByteString, age :: Integer, shopping :: [BuiltinByteString]}

PlutusTx.unstableMakeIsData ''SomeData

someData = SomeData {name = "cats", age = 42, shopping = ["apple", "tomato", "cheese"]}

fortyTwo = 42 :: Integer

myDatum = Datum $ PlutusTx.dataToBuiltinData $ PlutusTx.toData someData

myDatumHash = datumHash myDatum

{-
   Redeemers
-}

redeemerDatum = ExpInlineDatum {txOutRef = TxOutRef {txOutRefId = "b204b4554a827178b48275629e5eac9bde4f5350badecfcd108d87446f00bf26", txOutRefIdx = 0}, expDatum = myDatum}

redeemerDatumHash = ExpInlineDatumHash {txOutRef = TxOutRef {txOutRefId = "b204b4554a827178b48275629e5eac9bde4f5350badecfcd108d87446f00bf26", txOutRefIdx = 0}, expDatumHash = Just myDatumHash}

printRedeemerDatum = print $ "Redeemer Datum: " <> A.encode (scriptDataToJson ScriptDataJsonDetailedSchema $ fromPlutusData $ Plutus.Api.toData redeemerDatum)

printRedeemerDatumHash = print $ "Redeemer Datum Hash: " <> A.encode (scriptDataToJson ScriptDataJsonDetailedSchema $ fromPlutusData $ Plutus.Api.toData redeemerDatumHash)

{-
   The validator script
-}

{-# INLINEABLE expectedInlinePolicy #-}
expectedInlinePolicy :: ExpInline -> ScriptContext -> Bool
expectedInlinePolicy expInline ctx =
    case expInline of
    ExpInlineDatum {} ->
        traceIfFalse "ExpInlineDatum is not yet supported" False
    ExpInlineDatumHash {..} ->
        if isNothing expDatumHash
        then traceIfFalse "Expected txIn to have no datum hash but it does" noDatumHashInTxo
        else traceIfFalse "Expected txIn to have datum hash but it doesn't" datumHashInTxo
        where
            datumHashInTxo = expDatumHash P.== txOutDatumHash (txInInfoResolved findTxIn)
            noDatumHashInTxo = P.isNothing $ txOutDatumHash $ txInInfoResolved findTxIn
    where
        info :: TxInfo
        info = scriptContextTxInfo ctx

        fromJust' :: BuiltinString -> Maybe a -> a
        fromJust' err Nothing = traceError err
        fromJust' _ (Just x)  = x

        findTxIn :: TxInInfo
        findTxIn = fromJust' "txIn doesn't exist" $ findTxInByTxOutRef (txOutRef expInline) info

{-
    As a Minting Policy
-}

policy :: Scripts.MintingPolicy
policy = Plutus.mkMintingPolicyScript $$(PlutusTx.compile [||wrap||])
    where
        wrap = Scripts.wrapMintingPolicy expectedInlinePolicy

{-
    As a Script
-}

script :: Plutus.Script
script = Plutus.unMintingPolicyScript policy

{-
    As a Short Byte String
-}

scriptSBS :: SBS.ShortByteString
scriptSBS = SBS.toShort . LBS.toStrict $ serialise script

{-
    As a Serialised Script
-}

serialisedScript :: PlutusScript PlutusScriptV1
serialisedScript = PlutusScriptSerialised scriptSBS

writeSerialisedScript :: IO ()
writeSerialisedScript = void $ writeFileTextEnvelope "check-txo-inline.plutus" Nothing serialisedScript

{-

{-
    Offchain Contract
-}

scrAddress :: Ledger.Address
scrAddress = scriptAddress helloWorldValidator

valHash :: ValidatorHash
valHash = Ledger.validatorHash helloWorldValidator

helloWorldContract :: Contract () Empty Text ()
helloWorldContract = do
    logInfo @String $ "1: pay the script address"
    let tx1 = Constraints.mustPayToOtherScript valHash (Plutus.Datum $ hello) $ Ada.lovelaceValueOf 2000000
    ledgerTx <- submitTx tx1
    awaitTxConfirmed $ getCardanoTxId ledgerTx

    logInfo @String $ "2: spend from script address including \"Hello World!\" datum"
    utxos <- utxosAt scrAddress
    let orefs = fst <$> Map.toList utxos
        lookups = Constraints.otherScript helloWorldValidator <>
                  Constraints.unspentOutputs utxos
        tx2 = mconcat [Constraints.mustSpendScriptOutput oref unitRedeemer | oref <- orefs] <> -- List comprehension
              Constraints.mustIncludeDatum (Plutus.Datum $ BI.mkB "Not Hello World") -- doesn't seem to care what datum is
    ledgerTx <- submitTxConstraintsWith @Void lookups tx2
    awaitTxConfirmed $ getCardanoTxId ledgerTx
    logInfo @String $ "\"Hello World!\" tx successfully submitted"

{-
    Trace
-}

traceHelloWorld :: IO ()
traceHelloWorld = runEmulatorTraceIO helloWorldTrace

helloWorldTrace :: EmulatorTrace ()
helloWorldTrace = do
    void $ activateContractWallet (knownWallet 1) helloWorldContract
    void $ Emulator.nextSlot

-}
