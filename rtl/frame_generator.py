import math

def generate_donut_mem(filename="donut_data.mem", A=1.0, B=1.0):
    """
    Generates a 160x120 luminosity matrix for a single frame.
    Each pixel is mapped to a 4-bit value (0-15).
    """
    width, height = 160, 120
    R1, R2, K2 = 1, 2, 5
    
    # K1 factor adjusted to 1/4 (matching the "smaller" donut request)
    # This makes the donut fit comfortably within the 160x120 frame.
    K1 = width * K2 * 1 / (4 * (R1 + R2))
    
    # Initialize buffers
    # 19,200 pixels (160 * 120)
    matrix = [[0 for _ in range(width)] for _ in range(height)]
    zbuffer = [[0 for _ in range(width)] for _ in range(height)]

    # Precompute trig for the specific frame angles A and B
    cosA, sinA = math.cos(A), math.sin(A)
    cosB, sinB = math.cos(B), math.sin(B)

    # theta goes around the cross-sectional circle of a torus
    theta = 0
    while theta < 2 * math.pi:
        theta += 0.07 # theta_spacing
        phi = 0
        # phi goes around the center of revolution of a torus
        while phi < 2 * math.pi:
            phi += 0.02 # phi_spacing
            
            cosT, sinT = math.cos(theta), math.sin(theta)
            cosP, sinP = math.cos(phi), math.sin(phi)

            # circlex, circley: x,y coordinate of the circle before revolving
            circlex = R2 + R1 * cosT
            circley = R1 * sinT
            
            # Final 3D (x,y,z) coordinate after rotations
            x = circlex * (cosB * cosP + sinA * sinB * sinP) - circley * cosA * sinB
            y = circlex * (sinB * cosP - sinA * cosB * sinP) + circley * cosA * cosB
            z = K2 + cosA * circlex * sinP + circley * sinA
            ooz = 1 / z # "one over z"

            # 2D projection
            xp = int(width / 2 + K1 * ooz * x)
            yp = int(height / 2 - K1 * ooz * y) 

            # Calculate luminance (Normal vector dotted with light direction)
            # Ranges from -sqrt(2) to +sqrt(2)
            L = cosP * cosT * sinB - cosA * cosT * sinP - sinA * sinT + cosB * (cosA * sinT - cosT * sinA * sinP)

            # Check if within frame and if pixel is closer than current z-buffer
            if 0 <= xp < width and 0 <= yp < height:
                if ooz > zbuffer[yp][xp]:
                    zbuffer[yp][xp] = ooz
                    # Scale L (max ~1.41) to 4-bit range (0 to 15)
                    brightness = max(0, min(15, int((L / 1.41) * 15))) if L > 0 else 0
                    matrix[yp][xp] = brightness
            phi += 0.02

    # Write the result to a .mem file for Verilog $readmemh
    with open(filename, "w") as f:
        # We iterate Y then X to maintain a linear address: (Y * width) + X
        for y in range(height):
            for x in range(width):
                # Write a single hex digit (0-f) per line
                f.write(f"{matrix[y][x]:1x}\n")

if __name__ == "__main__":
    # Generate the frame for specific tilt (A) and rotation (B)
    generate_donut_mem("donut_data.mem", A=1.0, B=1.0)
    print("Success: donut_data.mem generated (19,200 pixels, 4-bit).")