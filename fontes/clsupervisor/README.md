# Corelabs Supervisor

Supervisor de processos da Corelabs OS 0.4 Sentinel.

## Responsabilidades

- Inicializar um processo supervisionado.
- Detectar encerramentos inesperados.
- Aplicar limites de reinicialização.
- Encaminhar sinais de encerramento.
- Aguardar o término dos processos filhos.
- Registrar eventos operacionais.

## Arquitetura inicial

Uma instância do supervisor por serviço.

O PID 1 continuará responsável pelo ciclo de vida
geral do sistema operacional.
