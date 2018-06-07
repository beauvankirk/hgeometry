{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE UndecidableInstances #-}
module Data.Geometry.Vector.VectorFamily where

import           Control.DeepSeq
import           Control.Lens hiding (element)
import           Data.Aeson (ToJSON(..),FromJSON(..))
import qualified Data.Foldable as F
import qualified Data.Geometry.Vector.VectorFixed as FV
import           Data.Proxy
import           Data.Traversable (foldMapDefault,fmapDefault)
import qualified Data.Vector.Fixed as V
import           GHC.TypeLits
import           Linear.Affine (Affine(..))
import           Linear.Metric
import qualified Linear.V2 as L2
import qualified Linear.V3 as L3
import qualified Linear.V4 as L4
import           Linear.Vector

--------------------------------------------------------------------------------
-- * d dimensional Vectors

-- | Datatype representing d dimensional vectors. The default implementation is
-- based n VectorFixed. However, for small vectors we automatically select a
-- more efficient representation.
newtype Vector (d :: Nat) (r :: *) = Vector { _unV :: VectorF d r }

-- | We select a vector depending on its length d
type VectorF (d :: Nat) = VectorFamily (SelectF d) d

-- | The different implementation types we consider
data SelectD = Zero | One | Two | Three | Four | Many

-- | Mapping from natural numbers to the different implementation types
type family SelectF (d :: Nat) where
  SelectF 0        = Zero
  SelectF 1        = One
  SelectF 2        = Two
  SelectF 3        = Three
  SelectF 4        = Four
  SelectF d        = Many

-- | Mapping between the implementation type, and the actual implementation.
type family VectorFamily (s :: SelectD) (d :: Nat) where
  VectorFamily Zero   d = Const ()
  VectorFamily One    d = Identity
  VectorFamily Two    d = L2.V2
  VectorFamily Three  d = L3.V3
  VectorFamily Four   d = L4.V4
  VectorFamily Many   d = FV.Vector d

-- | Class to select the particular vector implementation
class VectorSelect (s :: SelectD) where
  selectS :: proxy s
          -> f Zero
          -> f One
          -> f Two
          -> f Three
          -> f Four
          -> f Many
          -> f s

-- | Shortcut for selecting an implementation based on the type of d
select   :: forall proxy d f. Arity d
         => proxy d
         -> f Zero
         -> f One
         -> f Two
         -> f Three
         -> f Four
         -> f Many
         -> f (SelectF d)
select _ = selectS (Proxy :: Proxy (SelectF d))

instance VectorSelect Zero where
  selectS _ f0 _ _ _ _ _ = f0
instance VectorSelect One where
  selectS _ _ f1 _ _ _ _ = f1
instance VectorSelect Two where
  selectS _ _ _ f2 _ _ _ = f2
instance VectorSelect Three where
  selectS _ _ _ _ f3 _ _ = f3
instance VectorSelect Four where
  selectS _ _ _ _ _ f4 _ = f4
instance VectorSelect Many where
  selectS _ _ _ _ _ _ fm = fm


-- | To be able to select based on d, you basically need this constraint
type Arity d = (VectorSelect (SelectF d), V.Arity d)

--------------------------------------------------------------------------------

instance Arity d => Functor (Vector d) where
  fmap f =  Vector . go . _unV
    where
      d  = Proxy :: Proxy d
      go = runVF d $ select d (VecF $ fmap f)
                              (VecF $ fmap f)
                              (VecF $ fmap f)
                              (VecF $ fmap f)
                              (VecF $ fmap f)
                              (VecF $ fmap f)

newtype VecF d a b (s :: SelectD) =
  VecF { runVF' :: VectorFamily s d a -> VectorFamily s d b}
runVF   :: proxy d -> VecF d a b s -> VectorFamily s d a -> VectorFamily s d b
runVF _ = runVF'

instance Arity d => Foldable (Vector d) where
  foldMap = foldMapDefault
  length _ = fromInteger $ natVal (Proxy :: Proxy d)
  null v = length v == 0

instance Arity d => Traversable (Vector d) where
  traverse f = fmap Vector . go . _unV
    where
      d  = Proxy :: Proxy d
      go = runVT  d $ select d (VecT $ traverse f)
                               (VecT $ traverse f)
                               (VecT $ traverse f)
                               (VecT $ traverse f)
                               (VecT $ traverse f)
                               (VecT $ traverse f)

newtype VecT d a b f (s :: SelectD) = VecT (VectorFamily s d a -> f (VectorFamily s d b))

runVT            :: proxy d -> VecT d a b f s
                 -> VectorFamily s d a -> f (VectorFamily s d b)
runVT _ (VecT f) = f

--------------------------------------------------------------------------------

instance Arity d => Applicative (Vector d) where
  pure x = Vector . runVec d $ select d (p x) (p x) (p x) (p x) (p x) (p x)
    where
      d = Proxy :: Proxy d
      p :: (Applicative (VectorFamily s d)) => a -> Vec d a s
      p = Vec . pure

  g <*> u = Vector $ runApply d (select d a a a a a a) g u
    where
      d  = Proxy :: Proxy d
      a :: (Applicative (VectorFamily s d)) => Apply d a b s
      a = Apply $ \(Vector f) (Vector v) -> f <*> v

newtype Vec d r s = Vec (VectorFamily s d r)
runVec            :: proxy d -> Vec d r s -> VectorFamily s d r
runVec _ (Vec v) = v


newtype Apply d a b s =
  Apply (s ~ SelectF d => Vector d (a -> b) -> Vector d a -> VectorFamily s d b)

runApply             :: (Arity d, s ~ SelectF d)
                     => proxy d -> Apply d a b s
                     -> Vector d (a -> b) -> Vector d a -> VectorFamily s d b
runApply _ (Apply f) = f


--------------------------------------------------------------------------------

instance (Eq r, Arity d)   => Eq (Vector d r) where
  u == v = F.toList u == F.toList v
-- and $ (==) <$> u <*> v
instance (Ord r, Arity d)  => Ord (Vector d r) where
  u `compare` v = F.toList u `compare` F.toList v

instance (Show r, Arity d) => Show (Vector d r) where
  show v = mconcat [ "Vector", show $ length v , " "
                   , show $ F.toList v
                   ]
-- deriving instance (Arity d, NFData r) => NFData (Vector d r)

-- instance (FromJSON r, Arity d)  => FromJSON (Vector d r) where
--   parseJSON y = parseJSON y >>= \xs -> case vectorFromList xs of
--                   Nothing -> fail . mconcat $
--                     [ "FromJSON (Vector d a), wrong number of elements. Expected "
--                     , show $ natVal (Proxy :: Proxy d)
--                     , " elements but found "
--                     , show $ length xs
--                     , "."
--                     ]
--                   Just v -> pure v

instance (ToJSON r, Arity d) => ToJSON (Vector d r) where
  toJSON     = toJSON     . F.toList
  toEncoding = toEncoding . F.toList


instance Arity d => Additive (Vector d) where
  zero = pure 0
  u ^+^ v = (+) <$> u <*> v

instance Arity d => Affine (Vector d) where
  type Diff (Vector d) = Vector d
  u .-. v = u ^-^ v
  p .+^ v = p ^+^ v

instance Arity d => Metric (Vector d)

--------------------------------------------------------------------------------

type instance V.Dim (Vector d)  = d

-- instance V.Vector (Vector d) r where
--   construct  = Vector <$> V.construct
--   inspect    = V.inspect . _unV
--   basicIndex = V.basicIndex . _unV

type instance Index   (Vector d r) = Int
type instance IxValue (Vector d r) = r




--------------------------------------------------------------------------------
-- * Convenience "constructors"

pattern Vector1   :: r -> Vector 1 r
pattern Vector1 x = (Vector (Identity x))

pattern Vector2     :: r -> r -> Vector 2 r
pattern Vector2 x y = (Vector (L2.V2 x y))

pattern Vector3        :: r -> r -> r -> Vector 3 r
pattern Vector3 x y z  = (Vector (L3.V3 x y z))

pattern Vector4         :: r -> r -> r -> r -> Vector 4 r
pattern Vector4 x y z w = (Vector (L4.V4 x y z w))

--------------------------------------------------------------------------------


-- type instance V.Dim L2.V2 = 2
-- instance V.Vector L2.V2 r where
--   construct = V.Fun L2.V2
--   inspect (L2.V2 x y) (V.Fun f) = f x y
--   basicIndex (L2.V2 x y) = \case
--     0 -> x
--     1 -> y
--     _ -> error "Data.Geometry.Vector.VectorFamily.basicIndex: V2: element out of bounds"
-- type instance V.Dim L3.V3 = 3
-- instance V.Vector L3.V3 r where
--   construct = V.Fun L3.V3
--   inspect (L3.V3 x y z) (V.Fun f) = f x y z
--   basicIndex (L3.V3 x y z) = \case
--     0 -> x
--     1 -> y
--     2 -> z
--     _ -> error "Data.Geometry.Vector.VectorFamily.basicIndex: V3: element out of bounds"
-- type instance V.Dim L4.V4 = 4
-- instance V.Vector L4.V4 r where
--   construct = V.Fun L4.V4
--   inspect (L4.V4 x y z w) (V.Fun f) = f x y z w
--   basicIndex (L4.V4 x y z w) = \case
--     0 -> x
--     1 -> y
--     2 -> z
--     3 -> w
--     _ -> error "Data.Geometry.Vector.VectorFamily.basicIndex: V4: element out of bounds"

-- instance Vec d r => Ixed (Vector d r) where
--   ix i = unV.V.element i


-- element'   :: Vec d r => Int -> Traversal' (Vector d r) r
-- element' i = ix i

-- --------------------------------------------------------------------------------

-- -- -- | Lens into the i th element
-- -- element   :: forall proxy i d r. (Arity d, Arity i, (i + 1) <= d)
-- --           => proxy i -> Lens' (Vector d r) r
-- -- element _ = V.elementTy (Proxy :: Proxy i)



-- -- -- | Similar to 'element' above. Except that we don't have a static guarantee
-- -- -- that the index is in bounds. Hence, we can only return a Traversal
-- -- element'   :: forall d r. Arity d => Int -> Traversal' (Vector d r) r
-- -- element' i f v
-- --   | 0 <= i && i < fromInteger (natVal (C :: C d)) = f (v V.! i)
-- --                                                  <&> \a -> (v&V.element i .~ a)
-- --        -- Implementation based on that of Ixed Vector in Control.Lens.At
-- --   | otherwise                                     = pure v


-- -- destruct            :: (Vec d r, Vec (d + 1) r, 1 <= (d + 1))
-- --                     => Vector (d + 1) r -> (r, Vector d r)
-- -- destruct (Vector v) = (V.head v, Vector $ V.tail v)


-- -- -- vectorFromList :: Arity d => [a] -> Maybe (Vector d a)
-- -- vectorFromList = fmap Vector . V.fromListM

-- -- vectorFromListUnsafe :: V.Arity d => [a] -> Vector d a
-- -- vectorFromListUnsafe = Vector . V.fromList



-- -- instance (Applicative (VectorF d)) => Applicative (Vector d) where
-- --   pure x = Vector $ pure x
-- --   (Vector f) <*> (Vector x) = Vector $ f <*> x

-- -- instance Arity d => V.Vector (Vector d) r where
-- --   -- construct = fmap Vector . V.construct
-- --   inspect (Vector v) (V.Fun f) = V.inspect v f
-- -- -- instance Ixed (Vector 2 r) where
-- -- --   ix i f (Vector v) = undefined -- Vector <$> FV.element' i f v


-- -- instance (Arity d, d ~ (5+d0)) => Ixed (Vector d r) where
-- --   ix i f (Vector v) = Vector <$> FV.element' i f v


-- -- ' = case v' of
-- --     (V1 x) -> case i of
-- --                 0 -> V1 <$> f x
-- --                 _ -> pure v'
-- --     (V2 v) -> case i of
-- --                 0 -> V2 <$> L2._x f v
-- --                 1 -> V2 <$> L2._y f v
-- --                 _ -> pure v'
-- --     (V3 v) -> case i of
-- --                 0 -> V3 <$> L3._x f v
-- --                 1 -> V3 <$> L3._y f v
-- --                 2 -> V3 <$> L3._z f v
-- --                 _ -> pure v'
-- --     (V4 v) -> case i of
-- --                 0 -> V4 <$> L4._x f v
-- --                 1 -> V4 <$> L4._y f v
-- --                 2 -> V4 <$> L4._z f v
-- --                 3 -> V4 <$> L4._w f v
-- --                 _ -> pure v'
-- --     (VD v) -> VD <$> FV.element' i f v



-- -- instance Arity d => Ixed (Vector d r) where
-- --   ix i f v' = case v' of
-- --     (V1 x) -> case i of
-- --                 0 -> V1 <$> f x
-- --                 _ -> pure v'
-- --     (V2 v) -> case i of
-- --                 0 -> V2 <$> L2._x f v
-- --                 1 -> V2 <$> L2._y f v
-- --                 _ -> pure v'
-- --     (V3 v) -> case i of
-- --                 0 -> V3 <$> L3._x f v
-- --                 1 -> V3 <$> L3._y f v
-- --                 2 -> V3 <$> L3._z f v
-- --                 _ -> pure v'
-- --     (V4 v) -> case i of
-- --                 0 -> V4 <$> L4._x f v
-- --                 1 -> V4 <$> L4._y f v
-- --                 2 -> V4 <$> L4._z f v
-- --                 3 -> V4 <$> L4._w f v
-- --                 _ -> pure v'
-- --     (VD v) -> VD <$> FV.element' i f v

-- -- element   :: (Arity i, Arity d, (i+1) <= d) => proxy i -> Lens' (Vector d r) r
-- -- element i = singular $ ix (fromIntegral $ natVal i)
























-- -- class HasElement' (i :: Nat) (v :: * -> *) (b :: Bool) where
-- --   elementL :: Arity i => proxy0 b -> proxy i -> Lens' (v r) r

-- -- instance HasElement' 0 Identity False where
-- --   elementL _ _ = lens runIdentity (const Identity)
-- -- instance HasElement' 0 L2.V2 False where
-- --   elementL _ _ = L2._x
-- -- instance HasElement' 1 L2.V2 False where
-- --   elementL _ _ = L2._y
-- -- instance HasElement' 0 L3.V3 False where
-- --   elementL _ _ = L3._x
-- -- instance HasElement' 1 L3.V3 False where
-- --   elementL _ _ = L3._y
-- -- instance HasElement' 2 L3.V3 False where
-- --   elementL _ _ = L3._z
-- -- instance HasElement' 0 L4.V4 False where
-- --   elementL _ _ = L4._x
-- -- instance HasElement' 1 L4.V4 False where
-- --   elementL _ _ = L4._y
-- -- instance HasElement' 2 L4.V4 False where
-- --   elementL _ _ = L4._z
-- -- instance HasElement' 3 L4.V4 False where
-- --   elementL _ _ = L4._w

-- -- instance (Arity d, (i+1) <= d) => HasElement' i (FV.Vector d) True where
-- --   elementL _ = FV.element

-- -- class HasElement (i :: Nat) (d :: Nat) where
-- --   elementL' :: (Arity i, Arity d, (i+1) <= d)
-- --             => proxy0 d -> proxy i -> Lens' (VectorF d r) r

-- -- instance (v ~ VectorF d, b ~ (5 <=? d), HasElement' i v b) => HasElement i d where
-- --   elementL' _ = elementL (Proxy :: Proxy (5 <=? d))


-- -- element   :: forall proxy i d r. (Arity i, Arity d, (i+1) <= d, HasElement i d)
-- --           => proxy i -> Lens' (Vector d r) r
-- -- element i = unV.elementL' (Proxy :: Proxy d) i


-- -- vectorFromListUnsafe :: forall d r. Arity d => [r] -> Vector d r
-- -- vectorFromListUnsafe = \case
-- --     []             -> error "Data.Vector.VectorFamily.vectorFromListUnsafe: Empty vector"
-- --     [x] | expect 1 -> Vector (Identity x)

-- --   where
-- --     d = natVal (Proxy :: Proxy d)

-- --     expect l = d == l


-- -- class HasElement (i :: Nat) (d :: Nat) (b :: Bool) where
-- --   elementL :: (i <= d, Arity i, Arity d) => proxy0 b -> proxy i -> Lens' (Vector d r) r

-- -- instance HasElement 0 2 False where
-- --   elementL _ _ = unV.L2._x
-- -- instance HasElement 1 2 False where
-- --   elementL _ = unV.L2._y
-- -- instance HasElement 0 3 False where
-- --   elementL _ = unV.L3._x
-- -- instance HasElement 1 3 False where
-- --   elementL _ = unV.L3._y
-- -- instance HasElement 2 3 False where
-- --   elementL _ = unV.L3._z

-- -- instance HasElement i d True where
-- --   element _ px = unV.FV.element px


-- -- --------------------------------------------------------------------------------

-- -- | Cross product of two three-dimensional vectors
-- cross       :: Num r => Vector 3 r -> Vector 3 r -> Vector 3 r
-- (Vector u) `cross` (Vector v) = Vector $ u `L3.cross` v