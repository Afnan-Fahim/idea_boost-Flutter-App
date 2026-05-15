const {getAuth} = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");
const {onRequest} = require("firebase-functions/v2/https");
const nodemailer = require("nodemailer");

/**
 * Cloud Function: Send Professional Verification Email (via Gmail SMTP)
 * Built for "Elite Onboarding" - Branded button, no long URLs.
 */
module.exports = onRequest({region: "us-central1"}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const {email} = req.body;
  if (!email) return res.status(400).send("Email required");

  try {
    logger.info(`🚀 Sending Elite Verification Email to: ${email}`);

    // 1. Generate Link
    const verificationLink = await getAuth().generateEmailVerificationLink(email);

    // 2. Configure SMTP
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: process.env.GMAIL_USER,
        pass: process.env.GMAIL_PASS
      }
    });

    // 3. Ultra-Modern HTML (Neon Dark Mode)
    const mailOptions = {
      from: `"IdeaBoost Support" <${process.env.GMAIL_USER}>`,
      to: email,
      subject: "Welcome to the Elite: Verify Your IdeaBoost Account",
      text: `Welcome to IdeaBoost! Please verify your account here: ${verificationLink}`,
      html: `
        <div style="background-color: #020617; padding: 60px 20px; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; text-align: center;">
          <div style="max-width: 550px; margin: 0 auto; background-color: #0F172A; border-radius: 32px; padding: 50px; border: 1px solid #1E293B; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);">
            <div style="background: linear-gradient(135deg, #6366F1 0%, #A855F7 100%); width: 80px; height: 80px; border-radius: 20px; margin: 0 auto 30px; display: flex; align-items: center; justify-content: center; box-shadow: 0 10px 20px rgba(99, 102, 241, 0.3);">
              <span style="color: white; font-size: 40px; font-weight: bold; line-height: 80px;">⚡</span>
            </div>
            <h1 style="color: #F8FAFC; font-size: 32px; font-weight: 800; margin-bottom: 15px; letter-spacing: -0.5px;">Welcome to IdeaBoost</h1>
            <p style="color: #94A3B8; font-size: 17px; line-height: 1.7; margin-bottom: 35px;">
              You're one step away from unlocking the full power of IdeaBoost. Click the button below to verify your account and join the elite.
            </p>
            <a href="${verificationLink}" style="background: linear-gradient(135deg, #6366F1 0%, #A855F7 100%); color: #FFFFFF; padding: 20px 40px; text-decoration: none; border-radius: 16px; font-weight: 700; font-size: 18px; display: inline-block; box-shadow: 0 15px 30px rgba(99, 102, 241, 0.4); transition: all 0.3s ease;">
              Verify Account Now
            </a>
            <div style="margin-top: 50px; padding-top: 30px; border-top: 1px solid #1E293B;">
              <p style="color: #475569; font-size: 13px;">
                If you didn't create an account, you can safely ignore this email.
              </p>
            </div>
          </div>
        </div>
      `
    };

    // 4. Send Email
    await transporter.sendMail(mailOptions);
    
    logger.info(`✅ Verification Email delivered to: ${email}`);
    res.status(200).json({success: true});

  } catch (error) {
    logger.error("❌ Verification Error:", error);
    res.status(500).json({error: "Failed to deliver verification email"});
  }
});
