const {getAuth} = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");
const {onRequest} = require("firebase-functions/v2/https");
const nodemailer = require("nodemailer");

/**
 * Cloud Function: Send Professional Reset Email (via Gmail SMTP)
 * This is the "Master Solution" - Branded button, no long URLs.
 */
module.exports = onRequest({region: "us-central1"}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const {email} = req.body;
  if (!email) return res.status(400).send("Email required");

  try {
    logger.info(`🚀 Sending Elite Gmail Reset to: ${email}`);

    // 1. Generate Link
    const resetLink = await getAuth().generatePasswordResetLink(email);

    // 2. Configure SMTP
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: process.env.GMAIL_USER,
        pass: process.env.GMAIL_PASS
      }
    });

    // 3. Premium HTML (No long URLs at the bottom!)
    const mailOptions = {
      from: `"IdeaBoost Support" <${process.env.GMAIL_USER}>`,
      to: email,
      subject: "Password Reset for IdeaBoost",
      text: `Hello! Click this link to reset your password: ${resetLink}`,
      html: `
        <div style="background-color: #0F172A; padding: 50px 20px; font-family: 'Helvetica', sans-serif; text-align: center;">
          <div style="max-width: 600px; margin: 0 auto; background-color: #1E293B; border-radius: 20px; padding: 40px; border: 1px solid #334155;">
            <h1 style="color: #6366F1; font-size: 32px; margin-bottom: 20px;">⚡ IdeaBoost</h1>
            <h2 style="color: #FFFFFF; font-size: 24px;">Password Recovery</h2>
            <p style="color: #94A3B8; font-size: 16px; line-height: 1.6; margin-bottom: 30px;">
              Hello! We received a request to reset your password. Click the button below to secure your account.
            </p>
            <a href="${resetLink}" style="background: linear-gradient(135deg, #6366F1 0%, #A855F7 100%); color: #FFFFFF; padding: 18px 35px; text-decoration: none; border-radius: 12px; font-weight: bold; font-size: 18px; display: inline-block;">
              Reset Password
            </a>
            <p style="color: #475569; font-size: 12px; margin-top: 40px;">
              If you didn't request this, you can safely ignore this email.
            </p>
          </div>
        </div>
      `
    };

    // 4. Send Email
    await transporter.sendMail(mailOptions);
    
    logger.info(`✅ Elite Email delivered successfully to: ${email}`);
    res.status(200).json({success: true});

  } catch (error) {
    logger.error("❌ Fatal Error in Reset Function:", error);
    res.status(500).json({error: "Failed to deliver professional email"});
  }
});
