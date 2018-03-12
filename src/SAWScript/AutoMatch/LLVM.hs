{-# LANGUAGE LambdaCase    #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE CPP           #-}

module SAWScript.AutoMatch.LLVM where

import Control.Monad.State hiding (mapM)
import Control.Monad.Free

import Text.LLVM hiding (parseDataLayout, Array, Double, Float, FloatType, Void)
import Verifier.LLVM.Codebase hiding ( Global, ppSymbol, ppIdent, globalSym, globalType )
import Verifier.LLVM.Backend.SAW
import Verifier.SAW.SharedTerm

import SAWScript.Prover.Util(sawProxy)
import SAWScript.Value

--import Data.Maybe
import Data.Either
#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif

import SAWScript.AutoMatch.Interaction
import SAWScript.AutoMatch.Declaration
import SAWScript.AutoMatch.Util

-- | Parse an LLVM module into a list of declarations
--   Yields an Interaction so that we can talk to the user about what went wrong
getDeclsLLVM :: SharedContext -> LLVMModule -> IO (Interaction (Maybe [Decl]))
getDeclsLLVM sc (LLVMModule file mdl _) =

  let dataLayout = parseDataLayout $ modDataLayout mdl
      symbols = map defName (modDefines mdl)
  in do
    (sbe, _mem, _scLLVM) <- createSAWBackend' sawProxy dataLayout sc
    (warnings, cb) <- mkCodebase sbe dataLayout mdl
    return $ do
      forM_ warnings $ liftF . flip Warning () . show
      let (untranslateable, translations) =
            partitionEithers . for symbols $ \(Symbol name) ->
               maybe (Left name) Right $
                  symDefineToDecl =<< lookupDefine (Symbol name) cb

      when (not . null $ untranslateable) $ do
         separator ThinSep
         liftF . flip Warning () $ "No translation for the following signatures in " ++ file ++ ":"
         bulleted $ map (("'" ++) . (++ "'")) untranslateable

      return $ Just translations

   where

      symDefineToDecl symDefine =
         let Symbol name = sdName symDefine
             args = mapM (\(Ident an, at) -> Arg an <$> memTypeToStdType at) $ sdArgs symDefine
             retType = memTypeToStdType =<< sdRetType symDefine
         in Decl name <$> retType <*> args

      memTypeToStdType t = case t of
         IntType 8  -> Just $ bitSeqType 8
         IntType 16 -> Just $ bitSeqType 16
         IntType 32 -> Just $ bitSeqType 32
         IntType 64 -> Just $ bitSeqType 64
         FloatType  -> Nothing -- We don't support floating point types
         DoubleType -> Nothing -- We don't support floating point types
         PtrType (MemType _memType) -> Nothing
            --memTypeToStdType memType -- TODO: Support pointers
         ArrayType _size _memType -> Nothing -- TODO: Support arrays
         _ -> Nothing
