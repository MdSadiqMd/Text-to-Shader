defmodule TextToShaderApi.Router do
  use Plug.Router

  @frontend_origin System.get_env("FRONTEND_ORIGIN") || "https://two-tab-app.vercel.app"

  plug(CORSPlug, origin: [@frontend_origin])
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  @gemini_api_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"

  @http_timeout 60_000
  @recv_timeout 60_000

  post "/api/generate-shader" do
    %{"prompt" => prompt} = conn.body_params

    case generate_shader_from_llm(prompt) do
      {:ok, vertex_shader, fragment_shader} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            success: true,
            vertexShader: vertex_shader,
            fragmentShader: fragment_shader,
            shaderCode:
              "// Vertex Shader\n#{vertex_shader}\n\n// Fragment Shader\n#{fragment_shader}"
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{success: false, error: reason}))
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp generate_shader_from_llm(prompt) do
    api_key = System.get_env("GEMINI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error,
       "Missing GEMINI_API_KEY environment variable. Please set it before running the application."}
    else
      full_prompt = """
      You are an expert WebGL shader programmer. Create a creative, visually stunning WebGL shader pair (vertex and fragment shaders) based on this description: #{prompt}

      Follow these guidelines:
      - Use standard WebGL (GLSL ES) syntax
      - Include comments explaining key sections
      - Use essential uniforms like u_time, u_resolution, and u_mouse as needed
      - Ensure vertex and fragment shaders work together properly
      - Make creative use of mathematical functions for visual interest
      - Include fallbacks for any complex functions that might not be supported
      - Optimize for performance where possible

      Please return your answer in the following JSON format:
      {
        "vertexShader": "vertex shader code here (enclosed in ```glsl code blocks)",
        "fragmentShader": "fragment shader code here (enclosed in ```glsl code blocks)"
      }

      Example response:
      {
        "vertexShader": "```glsl\\nattribute vec4 a_position;\\nuniform mat4 u_modelViewMatrix;\\nuniform mat4 u_projectionMatrix;\\nvoid main() {\\n  // Transform the vertex position\\n  gl_Position = u_projectionMatrix * u_modelViewMatrix * a_position;\\n}\\n```",
        "fragmentShader": "```glsl\\nprecision mediump float;\\nuniform float u_time;\\nuniform vec2 u_resolution;\\nvoid main() {\\n  // Calculate normalized coordinates\\n  vec2 uv = gl_FragCoord.xy/u_resolution.xy;\\n  // Create a time-based color animation\\n  vec3 color = 0.5 + 0.5 * cos(u_time + uv.xyx + vec3(0,2,4));\\n  gl_FragColor = vec4(color, 1.0);\\n}\\n```"
      }

      Ensure your shaders are valid WebGL compatible GLSL code with no syntax errors.
      """

      request_body = %{
        contents: [
          %{
            parts: [
              %{
                text: full_prompt
              }
            ]
          }
        ],
        generationConfig: %{
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048
        }
      }

      url = "#{@gemini_api_url}?key=#{api_key}"

      headers = [
        {"Content-Type", "application/json"}
      ]

      options = [
        timeout: @http_timeout,
        recv_timeout: @recv_timeout
      ]

      case HTTPoison.post(url, Jason.encode!(request_body), headers, options) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          parse_gemini_response(body)

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          error_message = "Gemini API error (HTTP #{status_code}): #{body}"
          {:error, error_message}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error,
           "HTTP request to Gemini API failed: #{reason}. Make sure your API key is valid and has proper permissions."}
      end
    end
  end

  defp parse_gemini_response(body) do
    try do
      response = Jason.decode!(body)

      text =
        get_in(response, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])

      if is_nil(text) do
        {:error, "Failed to extract text from Gemini response"}
      else
        # IO.puts("Raw Gemini response text: #{text}")
        case extract_json_from_text(text) do
          {:ok, %{"vertexShader" => vertex_shader, "fragmentShader" => fragment_shader}} ->
            clean_vertex = clean_shader_code(vertex_shader)
            clean_fragment = clean_shader_code(fragment_shader)
            {:ok, clean_vertex, clean_fragment}

          {:ok, %{"vertexShader" => vertex_shader}} when is_binary(vertex_shader) ->
            clean_vertex = clean_shader_code(vertex_shader)

            default_fragment = """
            precision mediump float;
            uniform float u_time;
            uniform vec2 u_resolution;

            void main() {
              vec2 uv = gl_FragCoord.xy / u_resolution.xy;
              gl_FragColor = vec4(uv.x, uv.y, sin(u_time) * 0.5 + 0.5, 1.0);
            }
            """

            {:ok, clean_vertex, default_fragment}

          {:ok, %{"fragmentShader" => fragment_shader}} when is_binary(fragment_shader) ->
            clean_fragment = clean_shader_code(fragment_shader)

            default_vertex = """
            attribute vec4 a_position;
            void main() {
              gl_Position = a_position;
            }
            """

            {:ok, default_vertex, clean_fragment}

          {:error, _} ->
            extract_shaders_with_regex(text)
        end
      end
    rescue
      e ->
        {:error, "Failed to parse Gemini response: #{Exception.message(e)}"}
    end
  end

  defp clean_shader_code(code) do
    code
    |> String.replace(~r/^```(?:glsl)?\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  defp extract_json_from_text(text) do
    case Regex.run(~r/\{.*\}/s, text) do
      [json_str] ->
        try do
          Jason.decode(json_str)
        rescue
          _ -> {:error, "Failed to parse JSON from response"}
        end

      nil ->
        {:error, "No JSON found in response"}
    end
  end

  defp extract_shaders_with_regex(text) do
    vertex_pattern = ~r/(?:vertex shader|VERTEX SHADER):?[\s\S]*?```(?:glsl)?\s*([\s\S]*?)```/i

    fragment_pattern =
      ~r/(?:fragment shader|FRAGMENT SHADER):?[\s\S]*?```(?:glsl)?\s*([\s\S]*?)```/i

    vertex_shader =
      case Regex.run(vertex_pattern, text, capture: :all_but_first) do
        [code] ->
          String.trim(code)

        _ ->
          """
          attribute vec4 a_position;
          void main() {
            gl_Position = a_position;
          }
          """
      end

    fragment_shader =
      case Regex.run(fragment_pattern, text, capture: :all_but_first) do
        [code] ->
          String.trim(code)

        _ ->
          """
          precision mediump float;
          uniform float u_time;
          uniform vec2 u_resolution;

          void main() {
            vec2 uv = gl_FragCoord.xy / u_resolution.xy;
            gl_FragColor = vec4(uv.x, uv.y, sin(u_time) * 0.5 + 0.5, 1.0);
          }
          """
      end

    {:ok, vertex_shader, fragment_shader}
  end
end
