from flask import Flask, request, jsonify
import hmac, hashlib, os

app = Flask(__name__)
SECRET = os.getenv("GITHUB_WEBHOOK_SECRET", "")

def verify_signature(payload, signature):
    if not SECRET:
        print("⚠️ Missing GITHUB_WEBHOOK_SECRET")
        return False
    mac = hmac.new(SECRET.encode(), payload, hashlib.sha256)
    return hmac.compare_digest(f"sha256={mac.hexdigest()}", signature)

@app.route("/webhook", methods=["POST"])
def webhook():
    sig = request.headers.get("X-Hub-Signature-256")
    event = request.headers.get("X-GitHub-Event", "ping")
    payload = request.data

    if not verify_signature(payload, sig):
        print("❌ Invalid signature!")
        return jsonify({"error": "Invalid signature"}), 403

    if event == "ping":
        print("✅ Webhook connected (ping).")
        return jsonify({"message": "pong"}), 200

    if event == "pull_request":
        data = request.json
        pr = data["pull_request"]
        print(f"📬 PR Event: {data.get('action')} - '{pr['title']}' by {pr['user']['login']}")
        return jsonify({"status": "PR event received"}), 200

    print(f"Unhandled event: {event}")
    return jsonify({"message": "Event ignored"}), 200

if __name__ == "__main__":
    print("🚀 Flask Webhook running at http://0.0.0.0:5000/webhook")
    app.run(host="0.0.0.0", port=5000)
