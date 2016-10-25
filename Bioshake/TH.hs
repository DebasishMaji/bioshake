{-# LANGUAGE TemplateHaskell, TypeOperators, TypeSynonymInstances, FlexibleInstances #-}

module Bioshake.TH where

import Language.Haskell.TH
import Bioshake
import Data.List.Split
import Data.Char
import Control.Monad
import Development.Shake (cmd, CmdOption(Shell))
import Bioshake.Cluster.Torque (Config, submit, TOption(CPUs), getCPUs)
import Bioshake.Implicit(Implicit_, param_)
import Data.List

makeSingleTypes :: Name -> [Name] -> [Name] -> DecsQ
makeSingleTypes ty outtags transtags = do
  let name = nameBase ty
      Just mod = nameModule ty
      lastMod = last $ splitOn "." mod
      outbase = nameBase $ head outtags
      'I':'s':ext' = outbase
      ext = map toLower ext'


  path <- [d| instance Pathable a => Pathable (a :-> $(conT ty) c) where paths (a :-> _) = ["tmp" </> concatMap takeFileName (paths a) <.> lastMod <.> name <.> ext] |]

  tags <- forM outtags $ \t -> do
    a <- newName "a"
    c <- newName "c"
    return (InstanceD Nothing [AppT (ConT ''Pathable) (VarT a)] (AppT (ConT t) (AppT (AppT (ConT ''(:->)) (VarT a)) (AppT (ConT ty) (VarT c)))) [])

  transtags <- forM transtags $ \t -> do
    a <- newName "a"
    c <- newName "c"
    return (InstanceD Nothing [AppT (ConT ''Pathable) (VarT a), AppT (ConT t) (VarT a)] (AppT (ConT t) (AppT (AppT (ConT ''(:->)) (VarT a)) (AppT (ConT ty) (VarT c)))) [])


  return $ path ++ tags ++ transtags

makeMultiTypes :: Name -> [Name] -> [Name] -> DecsQ
makeMultiTypes ty outtags transtags = do
  let name = nameBase ty
      Just mod = nameModule ty
      lastMod = last $ splitOn "." mod
      outbase = nameBase $ head outtags
      'I':'s':ext' = outbase
      ext = map toLower ext'


  path <- [d| instance Pathable a => Pathable (a :-> $(conT ty) c) where paths (a :-> _) = map (\x -> "tmp" </> takeFileName x <.> lastMod <.> name <.> ext) (paths a) |]

  tags <- forM outtags $ \t -> do
    a <- newName "a"
    c <- newName "c"
    return (InstanceD Nothing [AppT (ConT ''Pathable) (VarT a)] (AppT (ConT t) (AppT (AppT (ConT ''(:->)) (VarT a)) (AppT (ConT ty) (VarT c)))) [])

  transtags <- forM transtags $ \t -> do
    a <- newName "a"
    c <- newName "c"
    return (InstanceD Nothing [AppT (ConT ''Pathable) (VarT a), AppT (ConT t) (VarT a)] (AppT (ConT t) (AppT (AppT (ConT ''(:->)) (VarT a)) (AppT (ConT ty) (VarT c)))) [])


  return $ path ++ tags ++ transtags

makeSingleThread ty tags fun = do
  let name = nameBase ty
      name' = map toLower name

  TyConI (DataD _ _ _ _ [NormalC con _] _) <- reify ty


  consName <- newName name'
  constructor <- return $ ValD (VarP consName) (NormalB (AppE (ConE con) (ConE '()))) []

  a <- newName "a"
  inputs <- newName "inputs"
  out <- newName "out"
  let tags' = map (\t -> AppT (ConT t) (VarT a)) $ ''Pathable : tags
  build <- return $ InstanceD Nothing tags' (AppT (AppT (ConT ''Buildable) (VarT a)) (AppT (ConT ty) (TupleT 0))) [FunD 'build [Clause [VarP a,VarP inputs,VarP out] (NormalB (AppE (AppE (VarE 'cmd) (ConE 'Shell)) (SigE (AppE (AppE (AppE (VarE fun) (VarE a)) (VarE inputs)) (VarE out)) (AppT ListT (ConT ''String))))) []]]

  return [constructor, build]

makeSingleCluster ty tags fun = do
  let name = nameBase ty
      name' = map toLower name

  TyConI (DataD _ _ _ _ [NormalC con conTypes] _) <- reify ty

  let (_, _:conTypes') = unzip conTypes
      conArrTypes = map (\t -> AppT ArrowT t) conTypes'
      funType = foldr (\l r -> AppT l r) (AppT (ConT ty) (ConT ''Config)) conArrTypes

  consName <- newName name'
  constructorSig <- return $ SigD consName (ForallT [] [AppT (ConT ''Implicit_) (ConT ''Config)] funType)
  constructor <- return $ ValD (VarP consName) (NormalB (AppE (ConE con) (VarE 'param_))) []

  a <- newName "a"
  inputs <- newName "inputs"
  out <- newName "out"
  config <- newName "config"
  let tags' = map (\t -> AppT (ConT t) (VarT a)) $ ''Pathable : tags
  build <- return $ InstanceD Nothing tags' (AppT (AppT (ConT ''Buildable) (VarT a)) (AppT (ConT ty) (ConT ''Config))) [FunD 'build [Clause [AsP a (ConP con (VarP config : replicate (length conArrTypes) WildP)),VarP inputs,VarP out] (NormalB (AppE (AppE (AppE (VarE 'submit) (SigE (AppE (AppE (AppE (VarE fun) (VarE a)) (VarE inputs)) (VarE out)) (AppT ListT (ConT ''String)))) (VarE config)) (AppE (ConE 'CPUs) (LitE (IntegerL 1))))) []]]

  return [constructorSig, constructor, build]

-- Multithreaded versions of the above

makeThreaded ty tags fun = do
  let name = nameBase ty
      name' = map toLower name

  TyConI (DataD _ _ _ _ [NormalC con conTypes] _) <- reify ty

  let (_, _:conTypes') = unzip conTypes
      conArrTypes = map (\t -> AppT ArrowT t) conTypes'
      funType = foldr (\l r -> AppT l r) (AppT (ConT ty) (ConT ''Threads)) conArrTypes

  consName <- newName name'
  constructorSig <- return $ SigD consName (ForallT [] [AppT (ConT ''Implicit_) (ConT ''Threads)] funType)
  constructor <- return $ ValD (VarP consName) (NormalB (AppE (ConE con) (VarE 'param_))) []

  a <- newName "a"
  b <- newName "b"
  inputs <- newName "inputs"
  out <- newName "out"
  t <- newName "t"
  let tags' = map (\t -> AppT (ConT t) (VarT a)) $ ''Pathable : tags
  build <- return $ InstanceD Nothing tags' (AppT (AppT (ConT ''Buildable) (VarT a)) (AppT (ConT ty) (ConT ''Threads))) [FunD 'build [Clause [AsP a (ConP con (AsP b (ConP 'Threads [VarP t]) : replicate (length conArrTypes) WildP)), VarP inputs,VarP out] (NormalB (AppE (AppE (VarE 'cmd) (ConE 'Shell)) (SigE (AppE (AppE (AppE (AppE (VarE fun) (VarE t)) (VarE a)) (VarE inputs)) (VarE out)) (AppT ListT (ConT ''String))))) []], FunD 'threads [Clause [WildP, AsP a (ConP con (AsP b (ConP 'Threads [VarP t]) : replicate (length conArrTypes) WildP))] (NormalB (VarE t)) []]]

  return [constructorSig, constructor, build]


makeCluster ty tags fun = do
  let name = nameBase ty
      name' = map toLower name

  TyConI (DataD _ _ _ _ [NormalC con conTypes] _) <- reify ty

  let (_, _:conTypes') = unzip conTypes
      conArrTypes = map (\t -> AppT ArrowT t) conTypes'
      funType = foldr (\l r -> AppT l r) (AppT (ConT ty) (ConT ''Config)) conArrTypes

  consName <- newName name'
  constructorSig <- return $ SigD consName (ForallT [] [AppT (ConT ''Implicit_) (ConT ''Config)] funType)
  constructor <- return $ ValD (VarP consName) (NormalB (AppE (ConE con) (VarE 'param_))) []

  a <- newName "a"
  inputs <- newName "inputs"
  out <- newName "out"
  config <- newName "config"
  let tags' = map (\t -> AppT (ConT t) (VarT a)) $ ''Pathable : tags
  build <- return $ InstanceD Nothing tags' (AppT (AppT (ConT ''Buildable) (VarT a)) (AppT (ConT ty) (ConT ''Config))) [FunD 'build [Clause [AsP a (ConP con (VarP config : replicate (length conArrTypes) WildP)),VarP inputs,VarP out] (NormalB (AppE (AppE (VarE 'submit) (SigE (AppE (AppE (AppE (AppE (VarE fun) (AppE (VarE 'getCPUs) (VarE config))) (VarE a)) (VarE inputs)) (VarE out)) (AppT ListT (ConT ''String)))) (VarE config))) []]]

  return [constructorSig, constructor, build]

-- For writing commands succinctly
class Args a where args :: a -> [String]

instance Args String where args = words
instance Args [String] where args = id

class CArgs a where cmdArgs :: [String] -> a

instance CArgs [String] where cmdArgs = id
instance (Args a, CArgs r) => CArgs (a -> r) where cmdArgs a r = cmdArgs $ a ++ args r

type a |-> b = a

run :: CArgs a => a |-> [String]
run = cmdArgs []

