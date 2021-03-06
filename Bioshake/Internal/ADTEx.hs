{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE ViewPatterns      #-}
module Bioshake.Internal.ADTEx where

import           Bioshake
import           Bioshake.TH
import           Control.Monad
import           Control.Monad.Trans        (lift)
import           Data.List
import           Development.Shake
import           Development.Shake.FilePath

data Call c = Call c deriving Show

buildADTEx _  a@(paths -> [normal, tumour]) [out] =
  let bed = getBED a
  in withTempDirectory' "tmp" "adtex" $ \tmpDir -> do
    let tmpDir' = tmpDir </> "out"
    () <- run "ADTEx.py"
      ["-n", normal]
      ["-t", tumour]
      ["-b", bed]
      ["-o", tmpDir']
    lift $ copyFile' (tmpDir' </> "cnv.result") out

$(makeSingleTypes ''Call [''IsTSV] [])
