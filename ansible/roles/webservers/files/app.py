from flask import Flask, render_template, jsonify
from flask_sqlalchemy import SQLAlchemy
import socket, os

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "192.168.56.14")
DB_NAME = os.environ.get("DB_NAME")
DB_USER = os.environ.get("DB_USER")
DB_PASS = os.environ.get("DB_PASS")

app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}/{DB_NAME}"
)
db = SQLAlchemy(app)

class Video(db.Model):
    __tablename__ = "videos"
    id = db.Column(db.Integer, primary_key=True)
    videotitle = db.Column(db.String(255))
    filepath = db.Column(db.String(255))
    uploadedate = db.Column(db.Date)
    views = db.Column(db.Integer)

@app.route("/")
def index():
    videos = Video.query.all()
    return render_template("index.html", videos=videos)

@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "hostname": socket.gethostname()
    }), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)