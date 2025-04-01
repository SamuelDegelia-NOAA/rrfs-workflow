import yaml, sys

yaml_file = sys.argv[1]

# Load the YAML
with open(yaml_file, "r") as file:
    yaml_data = file.readlines()

# Dynamically comment out the block
start_commenting = False
for i, line in enumerate(yaml_data):
    if "# Duplicate Check" in line:
        start_commenting = True
    if start_commenting:
        if line.strip():  # Avoid empty lines
            yaml_data[i] = "# " + line
        if line.strip() == "name: reduce obs space":  
            start_commenting = False

# Save the updated file
with open(f"{yaml_file}", "w") as file:
    file.writelines(yaml_data)
