<?php

declare(strict_types=1);

use PhpParser\Node;
use PhpParser\Node\Expr\Variable;
use PHPStan\Analyser\Scope;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;
use PHPStan\Type\ObjectType;
use PHPStan\Type\TypeCombinator;
use Shopware\Core\System\SalesChannel\SalesChannelContext;

/**
 * @implements Rule<Variable>
 */
final class SalesChannelContextVariableNameRule implements Rule
{
    private const string REQUIRED_NAME = 'salesChannelContext';
    private const string TARGET_CLASS  = SalesChannelContext::class;

    public function getNodeType(): string
    {
        return Variable::class;
    }

    public function processNode(Node $node, Scope $scope): array
    {
        if (!$node instanceof Variable) {
            return [];
        }

        if (!is_string($node->name)) {
            return [];
        }

        if ($node->name === self::REQUIRED_NAME) {
            return [];
        }

        $variableType            = TypeCombinator::removeNull($scope->getType($node));
        $salesChannelContextType = new ObjectType(self::TARGET_CLASS);

        if (!$salesChannelContextType->isSuperTypeOf($variableType)->yes()) {
            return [];
        }

        return [
            RuleErrorBuilder::message(sprintf(
                'Variable $%s holds a %s but must be named $%s.',
                $node->name,
                self::TARGET_CLASS,
                self::REQUIRED_NAME,
            ))->build(),
        ];
    }
}
