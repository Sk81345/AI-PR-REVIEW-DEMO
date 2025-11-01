from flask import Flask, request, jsonify
import hmac
import hashlib
import os

app = Flask(__name__)

# Load secret from environment
GITHUB_WEBHOOK_SECRET = os.environ.get("GITHUB_WEBHOOK_SECRET", "")

def verify_signature(payload, signature):
    """Verify GitHub webhook signature"""
    if not GITHUB_WEBHOOK_SECRET:
        print("⚠️ Missing GITHUB_WEBHOOK_SECRET")
        return False
    secret = bytes(GITHUB_WEBHOOK_SECRET, 'utf-8')
    mac = hmac.new(secret, msg=payload, digestmod=hashlib.sha256)
    expected_signature = f"sha256={mac.hexdigest()}"
    return hmac.compare_digest(expected_signature, signature)

@app.route("/webhook", methods=["POST"])
def github_webhook():
    """Main webhook route"""
    signature = request.headers.get('X-Hub-Signature-256')
    event = request.headers.get('X-GitHub-Event', 'ping')
    payload = request.data

    # Validate the signature
    if not verify_signature(payload, signature):
        print("❌ Invalid signature!")
        return jsonify({"error": "Invalid signature"}), 403

    # Handle ping event
    if event == "ping":
        print("✅ Webhook connected successfully (ping event).")
        return jsonify({"message": "pong"}), 200

    # Handle pull request events
    if event == "pull_request":
        data = request.json
        action = data.get("action")
        pr_title = data["pull_request"]["title"]
        pr_user = data["pull_request"]["user"]["login"]
        print(f"📬 PR Event: {action} - '{pr_title}' by {pr_user}")
        # (Later you can add AI review logic here)
        return jsonify({"status": "PR event received"}), 200

    print(f"Unhandled event type: {event}")
    return jsonify({"message": "Event ignored"}), 200


if __name__ == "__main__":
    print("🚀 Flask Webhook Server running on http://0.0.0.0:5000/webhook")
    app.run(host="0.0.0.0", port=5000)
