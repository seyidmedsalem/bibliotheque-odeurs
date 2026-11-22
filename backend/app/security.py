"""Mots de passe hachés (bcrypt) et jetons JWT."""
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import User

bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode(), hashed.encode())
    except ValueError:
        return False


def create_token(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def user_id_from_token(token: str) -> Optional[int]:
    try:
        return int(jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        return None


def current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer), db: Session = Depends(get_db)
) -> User:
    uid = user_id_from_token(creds.credentials) if creds else None
    user = db.get(User, uid) if uid is not None else None
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Connexion requise", headers={"WWW-Authenticate": "Bearer"})
    return user
