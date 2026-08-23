{% macro calculate_annual_interest(balance_column, rate_column) %}
    round(({{ balance_column }} * {{ rate_column }} / 100), 2)
{% endmacro %}
