import js from '@eslint/js';
import pluginVue from 'eslint-plugin-vue';
import globals from 'globals';

export default [
    {
        ignores: [
            'vendor/**',
            'node_modules/**',
            'public/**',
            'var/**',
        ],
    },

    js.configs.recommended,

    // Vue plugin base setup
    ...pluginVue.configs['flat/recommended'],

    {
        languageOptions: {
            ecmaVersion: 'latest',
            sourceType: 'module',
            globals: {
                ...globals.browser,
                ...globals.node,
                Shopware: 'readonly',
            },
        },
        rules: {
            'no-console': ['warn', { allow: ['warn', 'error'] }],
            'no-debugger': 'error',
            indent: ['error', 4, { SwitchCase: 1 }],
            'linebreak-style': ['error', 'unix'],
            'comma-dangle': ['error', 'always-multiline'],
            'no-unused-vars': ['error', { vars: 'all', args: 'after-used', ignoreRestSiblings: true }],
            'vue/multi-word-component-names': 'off',
            'vue/html-indent': ['error', 4],
        },
    },
];
