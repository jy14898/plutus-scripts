{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module CheckDatumIsInline
  ( serialisedScript,
    scriptSBS,
    script,
    writeSerialisedScript,
  )
where

import           Cardano.Api                    (writeFileTextEnvelope)
import           Cardano.Api.Shelley            (PlutusScript (..),
                                                 PlutusScriptV2)
import           Codec.Serialise
import qualified Data.ByteString.Lazy           as LBS
import qualified Data.ByteString.Short          as SBS
import           Data.Functor                   (void)
import qualified Ledger.Typed.Scripts           as Scripts
import qualified Plutus.Script.Utils.V2.Scripts as PSU.V2
import qualified Plutus.V2.Ledger.Api           as PlutusV2
import qualified Plutus.V2.Ledger.Contexts      as Contexts
import qualified PlutusTx
import           PlutusTx.Prelude               as P hiding (Semigroup (..),
                                                      unless, (.))
import           Prelude                        (IO, (.))

{-
   The validator script
-}

{-# INLINEABLE expectedInlineValidator #-}
expectedInlineValidator :: BuiltinData -> BuiltinData -> PlutusV2.ScriptContext -> P.Bool
expectedInlineValidator _ r ctx = traceIfFalse "Unexpected datum at own input" (checkInlineDatum ownInput)
    where
        ownInput :: PlutusV2.TxInInfo
        Just ownInput = Contexts.findOwnInput ctx

        checkInlineDatum :: PlutusV2.TxInInfo -> P.Bool
        checkInlineDatum txin = PlutusV2.OutputDatum (PlutusV2.Datum r) P.== PlutusV2.txOutDatum (PlutusV2.txInInfoResolved txin)

validator :: Scripts.Validator
validator = PlutusV2.mkValidatorScript $$(PlutusTx.compile [|| wrap ||])
     where
         wrap = PSU.V2.mkUntypedValidator expectedInlineValidator

script :: PlutusV2.Script
script = PlutusV2.unValidatorScript validator

{-
    As a Short Byte String
-}

scriptSBS :: SBS.ShortByteString
scriptSBS = SBS.toShort . LBS.toStrict $ serialise script

{-
    As a Serialised Script
-}

serialisedScript :: PlutusScript PlutusScriptV2
serialisedScript = PlutusScriptSerialised scriptSBS

writeSerialisedScript :: IO ()
writeSerialisedScript = void $ writeFileTextEnvelope "scripts/check-datum-is-inline.plutus" Nothing serialisedScript
