import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_API_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

console.log("Edge Function starting...");

serve(async (req) => {
  try {
    console.log("Received new request:", req.method, req.url);

    // Check API key
    console.log("GEMINI_API_KEY loaded:", !!GEMINI_API_KEY);
    if (!GEMINI_API_KEY) {
      console.error("GEMINI_API_KEY not found!");
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: missing API key" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Parse client request
    let message: string;
    try {
      const body = await req.json();
      message = body.message;
      console.log("Message received from client:", message);
    } catch (parseErr) {
      console.error("Failed to parse request body:", parseErr);
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body", details: parseErr.message }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Build payload for Gemini (AI Studio format)
    const bodyPayload = {
      contents: [
        {
          parts: [{ text: message }],
        },
      ],
    };
    console.log("Payload to Gemini API:", JSON.stringify(bodyPayload));

    // Call Gemini API
    let geminiRes: Response;
    try {
      geminiRes = await fetch(GEMINI_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-goog-api-key": GEMINI_API_KEY,
        },
        body: JSON.stringify(bodyPayload),
      });
    } catch (fetchErr) {
      console.error("Network/fetch error calling Gemini API:", fetchErr);
      return new Response(
        JSON.stringify({ error: "Failed to reach Gemini API", details: fetchErr.message }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log("Gemini API HTTP status:", geminiRes.status);

    // Parse Gemini response JSON
    let data: any;
    try {
      data = await geminiRes.json();
    } catch (jsonErr) {
      console.error("Failed to parse Gemini JSON response:", jsonErr);
      const rawText = await geminiRes.text();
      console.log("Raw response text from Gemini:", rawText);
      return new Response(
        JSON.stringify({ error: "Invalid JSON from Gemini", raw: rawText }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log("Gemini raw JSON response:", JSON.stringify(data, null, 2));

    // Extract text from Gemini response
    const geminiResponse =
      data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "No response from Gemini";

    console.log("Extracted Gemini response:", geminiResponse);

    return new Response(JSON.stringify({ response: geminiResponse }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Unexpected error in Edge Function:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
