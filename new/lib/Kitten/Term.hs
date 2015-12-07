{-# LANGUAGE OverloadedStrings #-}

module Kitten.Term
  ( Case(..)
  , Else(..)
  , Term(..)
  , Value(..)
  , compose
  , decompose
  , origin
  , type_
  ) where

import Data.List (intersperse)
import Data.Text (Text)
import Kitten.Intrinsic (Intrinsic)
import Kitten.Name
import Kitten.Operator (Fixity)
import Kitten.Origin (Origin)
import Kitten.Type (Type, TypeId)
import Text.PrettyPrint.HughesPJClass (Pretty(..))
import qualified Data.Text as Text
import qualified Kitten.Pretty as Pretty
import qualified Text.PrettyPrint as Pretty

-- This is the core language. It permits pushing values to the stack, invoking
-- definitions, and moving values between the stack and local variables.
--
-- It also permits empty programs and program concatenation. Together these form
-- a monoid over programs. The denotation of the concatenation of two programs
-- is the composition of the denotations of those two programs. In other words,
-- there is a homomorphism from the syntactic monoid onto the semantic monoid.

data Term
  = Call !(Maybe Type) !Fixity !GeneralName [Type] !Origin         -- f
  | Compose !(Maybe Type) !Term !Term                              -- e1 e2
  | Drop !(Maybe Type) !Origin                                     -- drop
  | Generic !TypeId !Term !Origin                                  -- Λx. e
  | Group !Term                                                    -- (e)
  | Identity !(Maybe Type) !Origin                                 --
  | If !(Maybe Type) !Term !Term !Origin                           -- if { e1 } else { e2 }
  | Intrinsic !(Maybe Type) !Intrinsic !Origin                     -- .add.int
  | Lambda !(Maybe Type) !Unqualified !(Maybe Type) !Term !Origin  -- → x; e
  | Match !(Maybe Type) [Case] !(Maybe Else) !Origin               -- match { case C {...}... else {...} }
  | New !(Maybe Type) !ConstructorIndex !Origin                    -- new.n
  | NewClosure !(Maybe Type) !Int !Origin                          -- new.closure.n
  | NewVector !(Maybe Type) !Int !Origin                           -- new.vec.n
  | Push !(Maybe Type) !Value !Origin                              -- push v
  | Swap !(Maybe Type) !Origin                                     -- swap
  deriving (Show)

data Case = Case !GeneralName !Term !Origin
  deriving (Show)

data Else = Else !Term !Origin
  deriving (Show)

data Value
  = Boolean !Bool
  | Character !Char
  | Closed !ClosureIndex
  | Closure [Closed] !Term
  | Float !Double
  | Integer !Integer
  | Local !LocalIndex
  | Name !Qualified
  | Quotation !Term
  | Text !Text
  deriving (Show)

compose :: Origin -> [Term] -> Term
compose o = foldr (Compose Nothing) (Identity Nothing o)

decompose :: Term -> [Term]
decompose (Compose _ a b) = decompose a ++ decompose b
decompose Identity{} = []
decompose term = [term]

origin :: Term -> Origin
origin term = case term of
  Call _ _ _ _ o -> o
  Compose _ a _ -> origin a
  Drop _ o -> o
  Generic _ _ o -> o
  Group a -> origin a
  Identity _ o -> o
  If _ _ _ o -> o
  Intrinsic _ _ o -> o
  Lambda _ _ _ _ o -> o
  New _ _ o -> o
  NewClosure _ _ o -> o
  NewVector _ _ o -> o
  Match _ _ _ o -> o
  Push _ _ o -> o
  Swap _ o -> o

-- Deduces the explicit type of a term.

type_ :: Term -> Maybe Type
type_ term = case term of
  Call t _ _ _ _ -> t
  Compose t _ _ -> t
  Drop t _ -> t
  Generic _ term' _ -> type_ term'
  Group term' -> type_ term'
  Identity t _ -> t
  If t _ _ _ -> t
  Intrinsic t _ _ -> t
  Lambda t _ _ _ _ -> t
  Match t _ _ _ -> t
  New t _ _ -> t
  NewClosure t _ _ -> t
  NewVector t _ _ -> t
  Push t _ _ -> t
  Swap t _ -> t

instance Pretty Term where
  pPrint term = case term of
    Call _ _ name [] _ -> pPrint name
    Call _ _ name args _ -> Pretty.hcat
      $ pPrint name : "<" : intersperse ", " (map pPrint args) ++ [">"]
    Compose _ a b -> pPrint a Pretty.$+$ pPrint b
    Drop _ _ -> "drop"
    Generic name body _ -> Pretty.hsep
      [Pretty.angles $ pPrint name, pPrint body]
    Group a -> Pretty.parens (pPrint a)
    Identity{} -> Pretty.empty
    If _ a b _ -> "if:"
      Pretty.$$ Pretty.nest 4 (pPrint a)
      Pretty.$$ "else:"
      Pretty.$$ Pretty.nest 4 (pPrint b)
    Intrinsic _ name _ -> pPrint name
    Lambda _ name _ body _ -> "->"
      Pretty.<+> pPrint name
      Pretty.<> ";"
      Pretty.$+$ pPrint body
    Match _ cases mElse _ -> Pretty.vcat
      [ "match:"
      , Pretty.nest 4 $ Pretty.vcat $ map pPrint cases
        ++ [pPrint else_ | Just else_ <- [mElse]]
      ]
    New _ (ConstructorIndex index) _ -> "new." Pretty.<> Pretty.int index
    NewClosure _ size _ -> "new.closure." Pretty.<> pPrint size
    NewVector _ size _ -> "new.vec." Pretty.<> pPrint size
    Push _ value _ -> pPrint value
    Swap{} -> "swap"

instance Pretty Case where
  pPrint (Case name body _) = Pretty.vcat
    [ Pretty.hcat ["case ", pPrint name, ":"]
    , Pretty.nest 4 $ pPrint body
    ]

instance Pretty Else where
  pPrint (Else body _) = Pretty.vcat ["else:", Pretty.nest 4 $ pPrint body]

instance Pretty Value where
  pPrint value = case value of
    Boolean True -> "true"
    Boolean False -> "false"
    Character c -> Pretty.quotes $ Pretty.char c
    Closed (ClosureIndex index) -> "closure." Pretty.<> Pretty.int index
    Closure names term -> Pretty.hcat
      [ Pretty.char '$'
      , Pretty.parens $ Pretty.list $ map pPrint names
      , Pretty.braces $ pPrint term
      ]
    Float f -> Pretty.double f
    Integer i -> Pretty.integer i
    Local (LocalIndex index) -> "local." Pretty.<> Pretty.int index
    Name n -> pPrint n
    Quotation body -> Pretty.braces $ pPrint body
    Text t -> Pretty.doubleQuotes $ Pretty.text $ Text.unpack t