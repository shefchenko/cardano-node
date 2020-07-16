module Cardano.CLI.Shelley.Run.Key
  ( ShelleyKeyCmdError
  , renderShelleyKeyCmdError
  , runKeyCmd
  ) where

import           Cardano.Prelude

import qualified Data.Text as Text

import           Control.Monad.Trans.Except (ExceptT)
import           Control.Monad.Trans.Except.Extra (firstExceptT, hoistEither,
                   newExceptT)

import           Cardano.Api.TextView (TextViewDescription (..))
import           Cardano.Api.Typed

import           Cardano.CLI.Byron.Key (ByronKeyFailure, CardanoEra (..),
                   readEraSigningKey, renderByronKeyFailure)
import           Cardano.CLI.Helpers
import           Cardano.CLI.Shelley.Parsers (ITNKeyFile (..), KeyCmd (..),
                   OutputFile (..), SigningKeyFile (..),
                   VerificationKeyFile (..))

data ShelleyKeyCmdError
  = ShelleyKeyCmdReadFileError !(FileError TextEnvelopeError)
  | ShelleyKeyCmdWriteFileError !(FileError ())
  | ShelleyKeyCmdByronKeyFailure !ByronKeyFailure
  | ShelleyKeyCmdItnKeyConvError !ConversionError
  deriving Show

renderShelleyKeyCmdError :: ShelleyKeyCmdError -> Text
renderShelleyKeyCmdError err =
  case err of
    ShelleyKeyCmdReadFileError fileErr -> Text.pack (displayError fileErr)
    ShelleyKeyCmdWriteFileError fileErr -> Text.pack (displayError fileErr)
    ShelleyKeyCmdByronKeyFailure e -> renderByronKeyFailure e
    ShelleyKeyCmdItnKeyConvError convErr -> renderConversionError convErr

runKeyCmd :: KeyCmd -> ExceptT ShelleyKeyCmdError IO ()
runKeyCmd cmd =
  case cmd of
    KeyConvertByronPaymentKey skfOld skfNew ->
      runConvertByronPaymentKey skfOld skfNew
    KeyConvertITNStakeKey itnKeyFile mOutFile ->
      runSingleITNKeyConversion itnKeyFile mOutFile

runConvertByronPaymentKey
  :: SigningKeyFile -- ^ Input file: old format
  -> SigningKeyFile -- ^ Output file: new format
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertByronPaymentKey skeyPathOld (SigningKeyFile skeyPathNew) = do
    sk <- firstExceptT ShelleyKeyCmdByronKeyFailure $
            readEraSigningKey ByronEra skeyPathOld
    firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
      writeFileTextEnvelope skeyPathNew (Just skeyDesc) (ByronSigningKey sk)
  where
    skeyDesc = TextViewDescription "Payment Signing Key"

runSingleITNKeyConversion
  :: ITNKeyFile
  -> Maybe OutputFile
  -> ExceptT ShelleyKeyCmdError IO ()
runSingleITNKeyConversion (ITNVerificationKeyFile (VerificationKeyFile vk)) mOutFile = do
  bech32publicKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $ readBech32 vk
  vkey <- hoistEither
    . first ShelleyKeyCmdItnKeyConvError
    $ convertITNVerificationKey bech32publicKey
  case mOutFile of
    Just (OutputFile fp) ->
      firstExceptT ShelleyKeyCmdWriteFileError
        . newExceptT
        $ writeFileTextEnvelope fp Nothing vkey
    Nothing -> print vkey

runSingleITNKeyConversion (ITNSigningKeyFile (SigningKeyFile sk)) mOutFile = do
  bech32privateKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $ readBech32 sk
  skey <- hoistEither
    . first ShelleyKeyCmdItnKeyConvError
    $ convertITNSigningKey bech32privateKey
  case mOutFile of
    Just (OutputFile fp) ->
      firstExceptT ShelleyKeyCmdWriteFileError
        . newExceptT
        $ writeFileTextEnvelope fp Nothing skey
    Nothing -> print skey
