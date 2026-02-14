from datetime import datetime

from app.extensions import db


class SupportTicket(db.Model):
    __tablename__ = "support_tickets"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    subject = db.Column(db.String(140), nullable=False)
    message = db.Column(db.Text, nullable=False)

    status = db.Column(db.String(32), nullable=False, default="open")  # open|in_progress|resolved|closed
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": int(self.id),
            "user_id": int(self.user_id),
            "subject": self.subject,
            "message": self.message,
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class SupportMessage(db.Model):
    __tablename__ = "support_messages"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, nullable=False, index=True)      # the non-admin user
    sender_role = db.Column(db.String(16), nullable=False)           # user/admin
    sender_id = db.Column(db.Integer, nullable=False)                # who sent

    body = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id": int(self.id),
            "thread_id": int(self.user_id),
            "user_id": int(self.user_id),
            "sender_role": self.sender_role,
            "sender_user_id": int(self.sender_id),
            "sender_id": int(self.sender_id),
            "body": self.body,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
