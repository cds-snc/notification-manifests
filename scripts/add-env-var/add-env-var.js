const inquirer = require('inquirer');
const fs = require('fs').promises;
const path = require('path');
const chalk = require('chalk');
const YAML = require('yaml');

/**
 * An object representing various components and their configurations.
 * Each component has a path to its YAML template and a section name that indicates where to insert the new variable.
 */
const COMPONENTS = {
    'API': {
        path: '../../helmfile/overrides/notify/api.yaml.gotmpl',
        section: 'api'
    },
    'ADMIN': {
        path: '../../helmfile/overrides/notify/admin.yaml.gotmpl',
        section: 'admin'
    },
    'Celery': {
        path: '../../helmfile/overrides/notify/celery.yaml.gotmpl',
        section: 'celeryCommon'
    },
    'Document Download': {
        path: '../../helmfile/overrides/notify/document-download.yaml.gotmpl',
        section: 'documentDownload'
    },
    'Documentation': {
        path: '../../helmfile/overrides/notify/documentation.yaml.gotmpl',
        section: 'image'
    }
};

/**
 * An object that maps environment names to their corresponding file paths.
 * Variables are added at the end of these files
 */
const ENVIRONMENTS = {
    'sandbox': '../../helmfile/overrides/sandbox.env',
    'dev': '../../helmfile/overrides/dev.env',
    'staging': '../../helmfile/overrides/staging.env',
    'production': '../../helmfile/overrides/production.env'
};

/**
 * Modifies a component file by adding a new variable to a specified section.
 *
 * @param {string} filePath - The path to the file to be modified.
 * @param {string} section - The section in the file where the variable should be added.
 * @param {string} varName - The name of the variable to add.
 * @param {string} value - The value of the variable to add.
 * @throws Will throw an error if the section is not found in the file.
 * @returns {Promise<void>} - A promise that resolves when the file has been successfully modified.
 */
async function modifyComponentFile(filePath, section, varName, value) {
    try {
        const content = await fs.readFile(filePath, 'utf8');
        const lines = content.split('\n');
        let inSection = false;
        let lastEntryIndex = -1;
        let sectionIndent = '';

        // Find the section and its last entry
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmedLine = line.trim();

            if (trimmedLine.startsWith(section + ':')) {
                inSection = true;
                sectionIndent = line.match(/^\s*/)[0];
                continue;
            }

            if (inSection) {
                // If we find a new section (line starts without spaces), we've gone too far
                if (trimmedLine.length > 0 && !line.startsWith(' ')) {
                    break;
                }
                // Keep track of the last non-empty line in the section
                if (trimmedLine.length > 0) {
                    lastEntryIndex = i;
                }
            }
        }

        if (lastEntryIndex === -1) {
            throw new Error(`Could not find section "${section}" in ${filePath}`);
        }

        // Insert the new variable immediately after the last entry
        lines.splice(lastEntryIndex + 1, 0, `${sectionIndent}  ${varName}: ${value}`);

        // Write back to file
        await fs.writeFile(filePath, lines.join('\n'));
        console.log(chalk.green(`✓ Updated ${filePath}`));
    } catch (error) {
        console.error(chalk.red(`Error updating ${filePath}: ${error.message}`));
        throw error;
    }
}

/**
 * Appends an environment variable to the specified file.
 *
 * @param {string} filePath - The path to the environment file.
 * @param {string} varName - The name of the environment variable to add.
 * @param {string} value - The value of the environment variable to add.
 * @returns {Promise<void>} A promise that resolves when the file has been updated.
 * @throws Will throw an error if the file cannot be updated.
 */
async function modifyEnvironmentFile(filePath, varName, value) {
    try {
        const content = await fs.appendFile(filePath, `${varName}: "${value}"\n`);
        console.log(chalk.green(`✓ Updated ${filePath}`));
    } catch (error) {
        console.error(chalk.red(`Error updating ${filePath}: ${error.message}`));
        throw error;
    }
}

async function main() {
    console.log(chalk.blue('------------------------------------'));
    console.log(chalk.blue('Environment Variable Creation Script'));
    console.log(chalk.blue('------------------------------------\n'));
    console.log(chalk.green('Notes:\n'));
    console.log(chalk.green('- This script updates various files to add the env vars. When it is done, double-check the changes to make sure there are no errors'));
    console.log(chalk.green('- Don\'t include quotes in variable names or values\n'));

    const answers = await inquirer.prompt([
        {
            type: 'input',
            name: 'varName',
            message: 'Enter the new environment variable name (i.e. FF_NEW_FEATURE):',
            validate: input => input.length > 0 || 'Variable name is required'
        },
        {
            type: 'checkbox',
            name: 'components',
            message: 'Select components:',
            choices: Object.keys(COMPONENTS),
            validate: input => input.length > 0 ? true : 'Select at least one component'
        },
        {
            type: 'list',
            name: 'scenario',
            message: 'Select the scenario type:',
            choices: [
                'Single value for all environments',
                'Environment-specific values',
                'Value based on environment name',
                'Base domain based'
            ]
        }
    ]);

    let value;
    let envValues = {};

    switch (answers.scenario) {
        case 'Single value for all environments':
            const singleValue = await inquirer.prompt({
                type: 'input',
                name: 'value',
                message: 'Enter the value:',
                validate: input => input.length > 0 || 'Value is required'
            });
            value = `"${singleValue.value}"`;
            break;

        case 'Environment-specific values':
            value = `"{{ .StateValues.${answers.varName} }}"`;
            const envPrompts = await inquirer.prompt(
                Object.keys(ENVIRONMENTS).map(env => ({
                    type: 'input',
                    name: env,
                    message: `Enter value for ${env}:`,
                    validate: input => input.length > 0 || `Value for ${env} is required`
                }))
            );
            envValues = envPrompts;
            break;

        case 'Value based on environment name':
            const prefix = await inquirer.prompt({
                type: 'input',
                name: 'value',
                message: 'Enter the prefix (e.g., notify-new-env-var-):',
                validate: input => input.length > 0 || 'Prefix is required'
            });
            value = `"${prefix.value}{{ .Environment.Name }}"`;
            break;

        case 'Base domain based':
            const urlPrefix = await inquirer.prompt({
                type: 'input',
                name: 'value',
                message: 'Enter the URL prefix (e.g., https://some-new-url.):',
                validate: input => input.length > 0 || 'URL prefix is required'
            });
            value = `"${urlPrefix.value}{{ requiredEnv \"BASE_DOMAIN\" }}"`;
            break;
    }

    console.log(chalk.blue('\nApplying changes...'));

    try {
        // Update component files
        for (const component of answers.components) {
            const { path: filePath, section } = COMPONENTS[component];
            await modifyComponentFile(filePath, section, answers.varName, value);
        }

        // Update environment files if needed
        if (answers.scenario === 'Environment-specific values') {
            for (const [env, envFile] of Object.entries(ENVIRONMENTS)) {
                await modifyEnvironmentFile(envFile, answers.varName, envValues[env]);
            }
        }

        console.log(chalk.green('\n✓ All changes applied successfully!'));
        console.log(chalk.yellow('\nRemember to run `helmfile sync` to apply the changes.'));
    } catch (error) {
        console.error(chalk.red('\n✗ Failed to apply all changes. Please check the errors above.'));
        process.exit(1);
    }
}

main().catch(console.error);